# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Failure(type: :invalid_record, errors: {...}) — тип ошибки, не hook, см. BaseService#validate_params
    # и README ("Contract validation — тип ошибки, не hook"): формат ответа решает хост,
    # матчингом по :type в точке рендера, а не переопределением hook'а на уровне сервиса.
    class CreateService < BaseService
      def execute(params)
        create_resource(params).fmap { |r| on_success(r) }.or { |r| on_failure(r) }
      end

      protected

      # Для возможности переопределить этот кусок кода в дочерних классах
      def create_resource(params)
        resource = scope.new(params)

        resource.save ? Success(resource) : Failure(resource)
      end

      def on_failure(record)
        Failure(type: :invalid_record, errors: ::DefineSimpleAction.deep_dup(record.errors.messages))
      end

      def on_success(record)
        record
      end
    end
  end
end
