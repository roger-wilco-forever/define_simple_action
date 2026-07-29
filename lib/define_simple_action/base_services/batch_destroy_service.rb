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
        destroy_resource(params).or { |not_removed| failure_message(not_removed) }
      end

      protected

      def remove_resources(relation)
        relation.destroy_all
      end

      def removed?(resource)
        resource.destroyed?
      end

      private

      # Для возможности переопределить этот кусок кода в дочерних классах
      def destroy_resource(params)
        records = remove_resources(resource_to_delete(params[:ids]))
        not_removed = records.reject { |record| removed?(record) }

        not_removed.empty? ? Success(records) : Failure(not_removed)
      end

      def failure_message(not_removed)
        Failure(type: :batch_destroy, errors: not_removed.flat_map { |record| record.errors.full_messages })
      end

      def resource_to_delete(ids)
        model.where(id: ids)
      end
    end
  end
end
