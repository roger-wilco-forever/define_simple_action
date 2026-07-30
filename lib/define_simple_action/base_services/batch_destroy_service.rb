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
      # #destroy_resource(params) удаляет всё, что нашёл #resource_to_delete(params[:ids]),
      # через #remove_resources; если хоть одна запись не удалилась (по #removed?) —
      # Failure(type: :batch_destroy, errors: [...]) с full_messages неудалившихся записей.
      def execute(params)
        destroy_resource(params).or { |not_removed| failure_message(not_removed) }
      end

      protected

      # Переопределяемая точка удаления — дефолт <tt>relation.destroy_all</tt>. Хосту с
      # soft-delete-гемом достаточно переопределить на <tt>relation.discard_all</tt>.
      def remove_resources(relation)
        relation.destroy_all
      end

      # Переопределяемая проверка результата — дефолт <tt>resource.destroyed?</tt>.
      # Переопределяется в паре с #remove_resources (например, на <tt>resource.discarded?</tt>).
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
