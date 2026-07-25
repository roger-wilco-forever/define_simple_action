# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class UpdateService < BaseService
      def execute(params)
        resource = model.find(params[:id])

        if update_resource(resource, params)
          after_mutation(model.name)
          Success(resource)
        else
          Failure(invalid_record_error(resource))
        end
      rescue ActiveRecord::InvalidForeignKey => e
        Failure(foreign_key_error(e))
      end

      protected

      def update_resource(resource, params)
        resource.update(params.except(:id))
      end
    end
  end
end
