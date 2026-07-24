# frozen_string_literal: true

# Динамически создаёт CRUD-actions в Rails-контроллере по конвенции имён.
#
# ==== Пример
#
#   class SomeController < ApplicationController
#     include DefineSimpleAction::Concern
#
#     define_simple_actions(
#       actions: %i[index show create update destroy],
#       model_name: 'SomeModel'
#     )
#
#     private
#
#     def resource_params
#       params.require(:some).permit(:some_attr)
#     end
#   end
#
# Хост-приложение обязано реализовать (иначе — NotImplementedError):
# * <tt>authorization_data</tt> — данные авторизации, передаваемые в сервис
# * <tt>serialize_for_action(name, result, service_params)</tt> — сериализация результата сервиса
#
# Хост-приложение может переопределить (есть дефолт):
# * <tt>around_action_execution(**) { ... }</tt> — обёртка вызова (например, кэш), дефолт — просто yield
# * <tt>fallback_service_namespace</tt> — неймспейс базовых сервисов, дефолт — nil (без фоллбэка)
# * <tt>make_response_#{format}</tt> — рендер конкретного формата ответа, из коробки есть только :json
module DefineSimpleAction
  module Concern
    ACTION_BATCH_DESTROY = "batch_destroy"
    ACTION_CREATE = "create"
    ACTION_DESTROY = "destroy"
    ACTION_INDEX = "index"
    ACTION_SHOW = "show"
    ACTION_SHOW_BY_SLUG = "show_by_slug"
    ACTION_UPDATE = "update"

    # Метод получения входящих параметров и http-статус успешного ответа по умолчанию
    CRUD_ACTION_DATA = {
      ACTION_BATCH_DESTROY => {
        params_method: :resource_batch_destroy_params,
        status: :ok
      },
      ACTION_CREATE => {
        params_method: :resource_create_params,
        status: :created
      },
      ACTION_DESTROY => {
        params_method: :resource_destroy_params,
        status: :no_content
      },
      ACTION_INDEX => {
        params_method: :resource_index_params,
        status: :ok
      },
      ACTION_SHOW => {
        params_method: :resource_show_params,
        status: :ok
      },
      ACTION_SHOW_BY_SLUG => {
        params_method: :resource_show_by_slug_params,
        status: :ok
      },
      ACTION_UPDATE => {
        params_method: :resource_update_params,
        status: :ok
      }
    }.freeze

    DEFAULT_RESPONSE_FORMATS = %i[json].freeze

    module ClassMethods
      # Создаёт action, если он не определён в классе
      #
      # * <tt>:actions</tt> — список необходимых actions, например <code>%i[index show create update destroy]</code>
      # * <tt>:model_name</tt> — имя модели (или класс), передаётся в сервис
      # * <tt>:use_cache</tt> — включить кэш (интерпретируется в <tt>around_action_execution</tt> хоста)
      # * <tt>:cache_expires_in</tt> — TTL кэша (интерпретируется хостом, gem значения не задаёт)
      # * <tt>:response_formats</tt> — форматы ответа, например <code>%i[json csv]</code>
      # * <tt>:notify_data</tt> — произвольные данные, прокидываются в сервис как есть
      def define_simple_actions( # rubocop:disable Metrics/ParameterLists
        actions:,
        model_name: nil,
        use_cache: false,
        cache_expires_in: nil,
        response_formats: DEFAULT_RESPONSE_FORMATS,
        notify_data: nil
      )
        actions.map(&:to_sym).each do |action|
          next if method_defined?(action)

          define_method(action) do
            define_simple_action(
              action.to_s, model_name, response_formats, notify_data, use_cache, cache_expires_in
            )
          end
        end
      end
    end

    # === Точки расширения (хуки) ===

    # Данные авторизации, передаются в сервис как <tt>authorization_data:</tt>.
    def authorization_data
      raise NotImplementedError, "#{self.class} must implement #authorization_data"
    end

    # Оборачивает вызов сервиса + сериализацию (например, кэшем и/или APM-спаном).
    # Дефолт — без обёртки.
    def around_action_execution(**)
      yield
    end

    # Превращает результат сервиса в тело ответа. Обязателен к реализации на стороне хоста —
    # gem сознательно не имеет мнения о том, каким сериализатором пользуется приложение.
    def serialize_for_action(name, result, service_params)
      raise NotImplementedError, "#{self.class} must implement #serialize_for_action"
    end

    # Неймспейс базовых сервисов, используется как фоллбэк, если <tt>"#{prefix}::#{action}Service"</tt>
    # не существует. <tt>nil</tt> — фоллбэка нет, NameError пробрасывается наружу.
    def fallback_service_namespace
      nil
    end

    # === Дефолтный (JSON) рендер ответа. Для остальных форматов хост добавляет свой
    # <tt>make_response_#{format}</tt>. ===

    def make_response_json(format, serialized_result, status)
      format.json { render json: serialized_result, status: }
    end

    # === Механизм диспетчеризации ===

    def define_simple_action(name, model_name, response_formats, notify_data, use_cache, cache_expires_in) # rubocop:disable Metrics/ParameterLists
      return head :not_acceptable if response_formats.exclude?(request.format.symbol)

      service_params = fetch_params_for_action(name)

      serialized_result, status = around_action_execution(
        name:, model_name:, service_params:, use_cache:, cache_expires_in:
      ) { fetch_serialized_result_and_status(name, model_name, service_params, notify_data) }

      respond_to do |format|
        response_formats.each do |response_format|
          public_send(:"make_response_#{response_format}", format, serialized_result, status)
        end
      end
    end

    def fetch_serialized_result_and_status(name, model_name, service_params, notify_data)
      result = fetch_service_for_action(name, model_name, notify_data).call(service_params)

      [serialize_for_action(name, result, service_params), fetch_status_for_action(name, result)]
    end

    # Получаем список параметров, если метод не определён — передаём <tt>params</tt>
    #
    # Метод можно определить:
    # * в контроллере <tt>fetch_params_for_#{name}</tt>
    # * в concern, название метода в <tt>CRUD_ACTION_DATA.dig(name, :params_method)</tt>
    def fetch_params_for_action(name)
      method_name = :"fetch_params_for_#{name}"
      return __send__(method_name) if respond_to?(method_name, true)

      default_method_name = CRUD_ACTION_DATA.dig(name, :params_method)
      return __send__(default_method_name) if default_method_name && respond_to?(default_method_name, true)

      params
    end

    # Определяем сервис, если не переопределён,
    # используется "#{prefix}::#{name.camelize}Service", с фоллбэком на
    # "#{fallback_service_namespace}::#{name.camelize}Service"
    #
    # Сервис можно определить:
    # * в контроллере <tt>fetch_service_for_#{name}</tt>
    # * создать класс <tt>"#{prefix}::#{name.camelize}Service"</tt>, prefix — <tt>class.name.delete_suffix('Controller')</tt>
    #
    # Сервис инстанцируется сkwargs <tt>authorization_data:, model:, notify_data:, validation_contract_name:</tt> —
    # это ожидаемый контракт конструктора сервиса.
    def fetch_service_for_action(name, model_name, notify_data)
      method_name = :"fetch_service_for_#{name}"
      return __send__(method_name) if respond_to?(method_name, true)

      service_params = {
        authorization_data:,
        model: model_name.is_a?(String) ? model_name.constantize : model_name,
        notify_data:,
        validation_contract_name: fetch_validation_contract_name_for_action(name)
      }.compact

      begin
        "#{prefix}::#{name.camelize}Service".constantize.new(**service_params)
      rescue NameError
        raise unless fallback_service_namespace

        "#{fallback_service_namespace}::#{name.camelize}Service".constantize.new(**service_params)
      end
    end

    # Определяем HTTP-статус ответа.
    #
    # Метод можно определить в контроллере: <tt>fetch_status_for_#{name}</tt>
    #
    # Ожидается, что <tt>result</tt> отвечает на <tt>#failure?</tt> (контракт Result/dry-monads).
    def fetch_status_for_action(name, result)
      method_name = :"fetch_status_for_#{name}"
      return __send__(method_name, result) if respond_to?(method_name, true)

      return :unprocessable_entity if result.failure?

      CRUD_ACTION_DATA.dig(name, :status) || :ok
    end

    # Определяем имя контракта валидации для конкретного action'а.
    #
    # Метод можно определить в контроллере: <tt>validation_contract_name_for_#{name}</tt>
    def fetch_validation_contract_name_for_action(name)
      method_name = :"validation_contract_name_for_#{name}"
      return __send__(method_name) if respond_to?(method_name, true)

      "#{prefix}::#{name.capitalize}Contract"
    end

    def prefix
      if self.class.constants.include?(:PREFIX)
        self.class.const_get(:PREFIX)
      else
        self.class.name.delete_suffix("Controller")
      end
    end

    def default_ordering
      "id asc"
    end

    def compacted_ransack_params(params)
      ransack_params = (params[:q] || {}).to_enum&.to_h
      ransack_params&.deep_symbolize_keys&.compact
    end

    def resource_batch_destroy_params
      { ids: params[:ids] }
    end

    def resource_create_params
      resource_params
    end

    def resource_destroy_params
      { id: Integer(params[:id]) }
    end

    def resource_index_params
      q = compacted_ransack_params(params)
      q[:s] ||= default_ordering if default_ordering

      {
        limit: params[:limit],
        limitless: params[:limitless],
        offset: params[:offset],
        q:
      }.compact
    end

    def resource_show_by_slug_params
      {
        q: params[:q]&.to_unsafe_h&.deep_symbolize_keys,
        slug: params[:slug]
      }.compact
    end

    def resource_show_params
      {
        id: Integer(params[:id]),
        q: params[:q]&.to_unsafe_h&.deep_symbolize_keys
      }.compact
    end

    def resource_update_params
      resource_params.merge(id: Integer(params[:id]))
    end

    def self.included(klass)
      klass.extend(ClassMethods)
    end
  end
end
