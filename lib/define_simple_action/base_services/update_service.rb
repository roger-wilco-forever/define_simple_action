# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Failure(type: :invalid_record, errors: {...}) — тип ошибки, не hook, см. CreateService.
    class UpdateService < BaseService
      def execute(params)
        attempt_update(model.find(params[:id]), params).fmap { |r| on_success(r) }.or { |r| on_failure(r) }
      end

      protected

      def update_resource(resource, params)
        resource.update(params.except(:id))
      end

      private

      def attempt_update(resource, params)
        update_resource(resource, params) ? Success({ resource: }) : Failure({ resource: })
      end

      def on_failure(record)
        Failure(type: :invalid_record, errors: ::DefineSimpleAction.deep_dup(record[:resource].errors.messages))
      end

      def on_success(record)
        record[:resource]
      end
    end
  end
end
