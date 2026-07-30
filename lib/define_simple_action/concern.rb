# frozen_string_literal: true

require_relative "concern/class_methods"
require_relative "concern/hooks"
require_relative "concern/dispatch"
require_relative "concern/resolution"
require_relative "concern/resource_params"

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
# * <tt>render_error(failure, options)</tt> — конверт ошибки; gem сознательно не решает
#   формат (см. README, "Failure(type: ..., errors: ...) — тип ошибки, не hook")
#
# <tt>serialize_for_action</tt> — уже не голый hook, а рабочий дефолт: резолвит
# класс-сериализатор по конвенции имён (как резолвится сервис) и рендерит через
# <tt>render_resource</tt>/<tt>render_error</tt>. Хост-приложение может переопределить (есть дефолт):
# * <tt>render_resource(serializer_class, object, options)</tt> — единственная точка, которая
#   знает о конкретной библиотеке сериализации (Blueprinter и т.д.), дефолт — `#call(object, options)`
# * <tt>set_serializer_name_for_#{action}</tt> / <tt>default_serializer_name(name)</tt> — имя класса-сериализатора,
#   дефолт — конвенция <tt>"#{prefix}::#{action.camelize}Serializer"</tt>
# * <tt>serializer_options(name, service_params)</tt> — опции, которые получает `render_resource`, дефолт — `{}`
# * <tt>encode_response(hash)</tt> — кодирование финального хэша в JSON, дефолт — `JSON.generate`
# * <tt>fetch_serializer_for_#{action}(result, service_params)</tt> — полный обход
#   вышеперечисленного, если определён
# * <tt>around_action_execution(**) { ... }</tt> — обёртка вызова (например, кэш), дефолт — просто yield
# * <tt>fallback_service_namespace</tt> — неймспейс базовых сервисов, дефолт — nil (без фоллбэка)
# * <tt>make_response_#{format}</tt> — рендер конкретного формата ответа, из коробки есть только :json
#
# Реализация разложена по под-модулям (все подмешиваются сюда же, ничего не меняется для
# хоста — как включал <tt>DefineSimpleAction::Concern</tt>, так и продолжает):
# * Concern::ClassMethods — DSL <tt>define_simple_actions</tt> на уровне класса
# * Concern::Hooks — точки расширения (см. выше)
# * Concern::Dispatch — формат → params → сервис → сериализация (включая дефолтный
#   <tt>serialize_for_action</tt>) → рендер
# * Concern::Resolution — резолвинг params/сервиса/статуса/контракта/сериализатора по
#   конвенции имён
# * Concern::ResourceParams — дефолтные <tt>resource_#{action}_params</tt>
module DefineSimpleAction
  module Concern
    # Имена CRUD-action'ов, которые понимает <tt>define_simple_actions</tt> "из коробки"
    # (используются и как ключи CRUD_ACTION_DATA, и в матчинге по имени action'а — см.
    # Concern::Dispatch#serialize_for_action).
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

    # <tt>response_formats:</tt> по умолчанию для <tt>define_simple_actions</tt>, если не
    # передан явно — только JSON.
    DEFAULT_RESPONSE_FORMATS = %i[json].freeze

    include Hooks
    include Dispatch
    include Resolution
    include ResourceParams

    # Домешивает ClassMethods (<tt>.define_simple_actions</tt>) в класс, который включает
    # Concern — обычный <tt>include</tt>-хук, а не что-то специфичное для этого gem'а.
    def self.included(klass)
      klass.extend(ClassMethods)
    end
  end
end
