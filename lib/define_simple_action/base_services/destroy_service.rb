# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class DestroyService < BaseService
      def execute(params)
        resource = destroy_resource(params)
        delete_action = call_hook(:soft_delete?, resource.class) ? :discard : :destroy

        if destroy_resource(params).public_send(delete_action)
          Success(resource)
        else
          record = destroy_resource(params)
          Failure(call_hook(:invalid_record_error, record) || { errors: record.errors.messages })
        end
      end

      protected

      # Для возможности переопределить этот кусок кода в дочерних классах
      def destroy_resource(params)
        @destroy_resource ||= scope(params).find(params[:id])
      end
    end
  end
end
