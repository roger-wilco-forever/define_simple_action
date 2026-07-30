# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Базовый сервис для DefineSimpleAction::Concern — принимает kwargs, которые
    # concern передаёт при резолвинге сервиса (authorization_data:, model:,
    # validation_contract_name:), валидирует params через dry-validation контракт
    # (резолвится по имени класса) и вызывает #execute.
    #
    # notify/notify_data — НЕ зона ответственности gem'а: concern по-прежнему нейтрально
    # прокидывает notify_data: в service_params (см. Concern#fetch_service_for_action),
    # но сам gem его не объявляет и не интерпретирует. Хосту, которому нужен notify,
    # достаточно публичных точек расширения (option, after_execute) — см. README,
    # раздел "Notify — не в gem'е".
    #
    # Форматы ошибок, инвалидация кэша, soft-delete-конвенция, выбор response-класса и
    # т.д. в gem'е не декларируются вообще — это либо обычные переопределяемые методы
    # (create_resource/remove_resource/build_response/...), либо after_execute (см. README).
    #
    # #validate_params — особый случай: это не hook (нечего вызывать до старта execute),
    # а тип ошибки прямо в Failure — Failure(type: :contract_validation, errors: {...}).
    # Формат ответа (envelope, коды ошибок и т.д.) gem не решает вообще; хост сам матчит
    # по :type в точке, где рендерит ответ (см. README, "Contract validation — тип ошибки,
    # не hook").
    class BaseService
      include Dry::Monads[:do, :maybe, :result, :try]
      include Callbacks
      extend Dry::Initializer

      option :authorization_data, optional: true, reader: :private
      option :model, optional: true, reader: :private
      option :validation_contract_name, optional: true, reader: :private

      PAGE_LENGTH = 100

      def self.call(params)
        new(**params).execute(params[:params])
      end

      def call(params)
        yield(validate_params(params))
        @service_params = params

        yield(run_before_execute_callbacks(params))

        instrumented_execute(params).tap { |result| run_after_execute_callbacks(result) }
      end

      # Валидируем входящие параметры. Контракт резолвится:
      # 1. Из <tt>validation_contract_name</tt>
      # 2. По имени текущего класса: <tt>self.class.to_s.gsub(/Service\z/, 'Contract')</tt>
      # 3. По имени родительского класса
      def validate_params(params)
        contract.new.call(params)
                .to_monad
                .or do |error|
                  Failure(type: :contract_validation, errors: ::DefineSimpleAction.deep_dup(error.errors.to_h))
                end
      end

      protected

      attr_reader :service_params

      # Оборачивает #execute dry-monitor'ным событием "define_simple_action.execute"
      # (service, model, success, time) — публикуется всегда; подписка (метрики, логи,
      # трейсинг) целиком на хосте, см. DefineSimpleAction.notifications.
      def instrumented_execute(params)
        payload = { service: self.class.name, model: model }

        ::DefineSimpleAction.notifications.instrument('define_simple_action.execute', payload) do
          execute(**params).tap { |result| payload[:success] = result.success? }
        end
      end

      def contract
        validation_contract = validation_contract_name && ::DefineSimpleAction.safe_constantize(validation_contract_name)
        validation_contract ||= ::DefineSimpleAction.safe_constantize(self.class.to_s.gsub(/Service\z/, 'Contract'))
        validation_contract ||= ::DefineSimpleAction.safe_constantize(self.class.superclass.name.gsub(/Service\z/,
                                                                                                      'Contract'))

        if validation_contract.nil?
          raise(NotImplementedError, "Validation contract not found for #{self.class} " \
                                      "(expected #{validation_contract_name.inspect})")
        end

        validation_contract
      end

      def current_user
        return @current_user if defined?(@current_user)

        @current_user = authorization_data&.fetch(:current_user, nil)
      end

      def scope(_params = nil)
        model
      end

      def transform_result(result)
        Success(result)
      end
    end
  end
end
