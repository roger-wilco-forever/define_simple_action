# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Failure(type: :invalid_record, errors: {...}) — тип ошибки, не hook, см. CreateService.
    class UpdateService < BaseService
      def execute(params)
        resource = model.find(params[:id])

        if update_resource(resource, params)
          Success(resource)
        else
          Failure(type: :invalid_record, errors: ::DefineSimpleAction.deep_dup(resource.errors.messages))
        end
      end

      protected

      def update_resource(resource, params)
        resource.update(params.except(:id))
      end
    end
  end
end
