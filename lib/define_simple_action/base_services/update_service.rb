# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class UpdateService < BaseService
      def execute(params)
        resource = model.find(params[:id])

        if update_resource(resource, params)
          call_hook(:after_mutation, model.name)
          Success(resource)
        else
          Failure(call_hook(:invalid_record_error, resource) || { errors: resource.errors.messages })
        end
      rescue ActiveRecord::InvalidForeignKey => e
        Failure(call_hook(:foreign_key_error, e) || { error: e.message })
      end

      protected

      def update_resource(resource, params)
        resource.update(params.except(:id))
      end
    end
  end
end
