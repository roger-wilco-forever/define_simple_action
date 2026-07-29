# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Failure(type: :batch_destroy, errors: [...]) — тип ошибки, не hook, см. CreateService.
    #
    # Удаление — не hook (call_hook(:soft_delete?, ...)), а обычные переопределяемые методы
    # (#remove_resources/#removed?): дефолт — plain #destroy_all/#destroyed?, gem ничего не
    # знает про discard или другой soft-delete-гем. Хосту, которому нужен soft-delete,
    # достаточно переопределить оба метода в дочернем классе — никакого стороннего
    # ORM-словаря в самом gem'е.
    class BatchDestroyService < BaseService
      def execute(params)
        destroy_resource(params)
      end

      protected

      def remove_resources(relation)
        relation.destroy_all
      end

      def removed?(resource)
        resource.destroyed?
      end

      private

      def destroy_resource(params)
        destroyed(params)

        return failure_message(errors) if errors.any?

        Success(@destroyed)
      end

      def destroyed(params)
        @destroyed ||= remove_resources(resource_to_delete(params[:ids]))
      end

      def errors
        not_destroyed.flat_map { |r| r.errors.full_messages } || []
      end

      def failure_message(errors)
        Failure(type: :batch_destroy, errors:)
      end

      def not_destroyed
        @not_destroyed ||= @destroyed.reject { |r| removed?(r) }
      end

      def resource_to_delete(ids)
        @resource_to_delete ||= model.where(id: ids)
      end
    end
  end
end
