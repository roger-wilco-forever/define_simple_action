# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Failure(type: :batch_destroy, errors: [...]) — тип ошибки, не hook, см. CreateService.
    class BatchDestroyService < BaseService
      def execute(params)
        destroy_resource(params)
      end

      private

      def destroy_resource(params)
        destroyed(params)

        return failure_message(errors) if errors.any?

        Success(@destroyed)
      end

      def destroyed(params)
        @destroyed ||= resource_to_delete(params[:ids]).public_send(method_for_delete)
      end

      def errors
        not_destroyed.flat_map { |r| r.errors.full_messages } || []
      end

      def failure_message(errors)
        Failure(type: :batch_destroy, errors:)
      end

      def method_for_delete
        call_hook(:soft_delete?, model) ? :discard_all : :destroy_all
      end

      def not_destroyed
        @not_destroyed ||=
          if method_for_delete == :destroy_all
            @destroyed.reject(&:destroyed?)
          else
            @destroyed.reject(&:discarded?)
          end
      end

      def resource_to_delete(ids)
        @resource_to_delete ||= model.where(id: ids)
      end
    end
  end
end
