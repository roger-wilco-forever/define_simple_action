# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    # Резолвинг по конвенции имён: params-метод, сервис, http-статус, имя контракта.
    module Resolution
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
          model: model_name.is_a?(String) ? ::DefineSimpleAction.constantize(model_name) : model_name,
          notify_data:,
          validation_contract_name: fetch_validation_contract_name_for_action(name)
        }.compact

        camelized_name = ::DefineSimpleAction::INFLECTOR.camelize(name)

        begin
          ::DefineSimpleAction.constantize("#{prefix}::#{camelized_name}Service").new(**service_params)
        rescue NameError
          raise unless fallback_service_namespace

          ::DefineSimpleAction.constantize("#{fallback_service_namespace}::#{camelized_name}Service").new(**service_params)
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
    end
  end
end
