# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Базовый сервис для DefineSimpleAction::Concern — принимает kwargs, которые
    # concern передаёт при резолвинге сервиса (authorization_data:, model:, notify_data:,
    # validation_contract_name:), валидирует params через dry-validation контракт
    # (резолвится по имени класса) и вызывает #execute.
    #
    # Ошибки, кэш, soft-delete и капча — точки расширения (хуки), см. README.
    class BaseService
      include Dry::Monads[:do, :maybe, :result, :try]
      extend Dry::Initializer

      option :authorization_data, optional: true, reader: :private
      option :model, optional: true, reader: :private
      option :notify_data, optional: true, reader: :private
      option :validation_contract_name, optional: true, reader: :private

      PAGE_LENGTH = 100

      def self.call(params)
        new(**params).execute(params[:params])
      end

      def call(params)
        yield(validate_params(params))
        @service_params = params

        execute(**params).fmap do |result|
          notify(result) if notify_data&.dig(:watch_keys)&.any?
          result
        end
      end

      # Валидируем входящие параметры. Контракт резолвится:
      # 1. Из <tt>validation_contract_name</tt>
      # 2. По имени текущего класса: <tt>self.class.to_s.gsub(/Service\z/, 'Contract')</tt>
      # 3. По имени родительского класса
      def validate_params(params)
        contract.new.call(params)
                .to_monad
                .or { |error| Failure(contract_validation_error(error)) }
      end

      protected

      attr_reader :service_params

      # === Хуки ===

      def after_mutation(model_name); end

      def batch_destroy_error(errors)
        { errors: }
      end

      def captcha_verify(_params)
        raise NotImplementedError, "#{self.class} must implement #captcha_verify"
      end

      def contract_validation_error(validation_result)
        { errors: validation_result.errors.to_h }
      end

      def foreign_key_error(exception)
        { error: exception.message }
      end

      def invalid_record_error(record)
        { errors: record.errors.messages }
      end

      def soft_delete?(_model_class)
        false
      end

      def unexpected_error(exception)
        { error: exception.message }
      end

      def notify(resource); end

      # === Общая логика ===

      def contract
        validation_contract = validation_contract_name&.safe_constantize
        validation_contract ||= self.class.to_s.gsub(/Service\z/, 'Contract').safe_constantize
        validation_contract ||= self.class.superclass.name.gsub(/Service\z/, 'Contract').safe_constantize

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
