# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class CreateService < BaseService
      def execute(params)
        create_resource(params).fmap { |r| on_success(r) }.or { |r| on_failure(r) }
      rescue StandardError => e
        raise e if optional_error?(e, 'ActiveRecord::RecordNotFound')

        if optional_error?(e, 'ActiveRecord::InvalidForeignKey')
          Failure(call_hook(:foreign_key_error, e) || { error: e.message })
        else
          Failure(call_hook(:unexpected_error, e) || { error: e.message })
        end
      end

      protected

      # Для возможности переопределить этот кусок кода в дочерних классах
      def create_resource(params)
        resource = scope.new(params)

        resource.save ? Success({ resource: }) : Failure({ resource: })
      end

      def on_failure(record)
        Failure(call_hook(:invalid_record_error, record[:resource]) || { errors: record[:resource].errors.messages })
      end

      def on_success(record)
        call_hook(:after_mutation, model.name)

        record[:resource]
      end
    end
  end
end
