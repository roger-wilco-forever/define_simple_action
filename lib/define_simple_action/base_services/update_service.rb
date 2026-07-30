# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Failure(type: :invalid_record, errors: {...}) — тип ошибки, не hook, см. CreateService.
    class UpdateService < BaseService
      # <tt>model.find(params[:id])</tt> → #update_resource(resource, params) → Success/Failure(resource)
      # → #on_success/#on_failure.
      def execute(params)
        attempt_update(model.find(params[:id]), params).fmap { |r| on_success(r) }.or { |r| on_failure(r) }
      end

      protected

      # Переопределяемая точка обновления — дефолт <tt>resource.update(params.except(:id))</tt>.
      # Должна вернуть truthy/falsy (как ActiveRecord <tt>#update</tt>), а не Success/Failure.
      def update_resource(resource, params)
        resource.update(params.except(:id))
      end

      private

      def attempt_update(resource, params)
        update_resource(resource, params) ? Success(resource) : Failure(resource)
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
