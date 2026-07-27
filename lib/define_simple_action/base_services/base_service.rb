# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Базовый сервис для DefineSimpleAction::Concern — принимает kwargs, которые
    # concern передаёт при резолвинге сервиса (authorization_data:, model:, notify_data:,
    # validation_contract_name:), валидирует params через dry-validation контракт
    # (резолвится по имени класса) и вызывает #execute.
    #
    # Хуки (форматы ошибок, инвалидация кэша, soft-delete-конвенция и т.д.) в gem'е
    # не декларируются — см. #call_hook. Хост определяет только те, что ему реально
    # нужны, под любым именем, которое ожидает точка вызова (см. README).
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
          call_hook(:notify, result) if notify_data&.dig(:watch_keys)&.any?
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
                .or { |error| Failure(call_hook(:contract_validation_error, error) || { errors: error.errors.to_h }) }
      end

      protected

      attr_reader :service_params

      # Вызывает метод <tt>name</tt>, если хост его определил (под любым именем,
      # которое ожидает конкретная точка вызова — contract_validation_error,
      # invalid_record_error, foreign_key_error, unexpected_error, batch_destroy_error,
      # after_mutation, soft_delete?, notify, ...), иначе возвращает nil — дефолт
      # подставляется на месте вызова через <tt>||</tt>. Ни один из этих хуков не
      # декларируется в gem'е как метод: хост создаёт только то, что ему нужно.
      #
      # ВАЖНО: сюда специально не завели blockдефолт (<tt>yield</tt>/<tt>&block</tt>) —
      # класс подключает Dry::Monads[:do], который автоматически оборачивает КАЖДЫЙ
      # метод класса в do-нотацию; внутри такого метода "yield"/"block_given?"
      # перехватывается do-machinery (ожидающей монаду), а не блоком вызывающего.
      def call_hook(name, *args)
        __send__(name, *args) if respond_to?(name, true)
      end

      def contract
        validation_contract = validation_contract_name && ::DefineSimpleAction.safe_constantize(validation_contract_name)
        validation_contract ||= ::DefineSimpleAction.safe_constantize(self.class.to_s.gsub(/Service\z/, 'Contract'))
        validation_contract ||= ::DefineSimpleAction.safe_constantize(self.class.superclass.name.gsub(/Service\z/, 'Contract'))

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

      # Проверка "exception — экземпляр класса с этим полным именем, если такой класс
      # вообще определён в рантайме". ActiveRecord/discard — не зависимости gem'а, а
      # опциональные интеграции хоста: если их нет — просто false, exception летит дальше.
      def optional_error?(exception, full_class_name)
        klass = ::DefineSimpleAction.safe_constantize(full_class_name)
        klass && exception.is_a?(klass)
      end
    end
  end
end
