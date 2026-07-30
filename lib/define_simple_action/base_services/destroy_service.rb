# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Failure(type: :invalid_record, errors: {...}) — тип ошибки, не hook, см. CreateService.
    #
    # Удаление — не hook (call_hook(:soft_delete?, ...)), а обычный переопределяемый метод
    # (#remove_resource): дефолт — plain #destroy, gem ничего не знает про discard или другой
    # soft-delete-гем. Хосту, которому нужен soft-delete, достаточно переопределить
    # #remove_resource в дочернем классе — никакого стороннего ORM-словаря в самом gem'е.
    class DestroyService < BaseService
      # #destroy_resource(params) → #remove_resource(resource) → Success/Failure(resource)
      # → #on_success/#on_failure.
      def execute(params)
        attempt_removal(destroy_resource(params)).fmap { |r| on_success(r) }.or { |r| on_failure(r) }
      end

      protected

      # Для возможности переопределить этот кусок кода в дочерних классах
      def destroy_resource(params)
        scope(params).find(params[:id])
      end

      # Переопределяемая точка удаления — дефолт <tt>resource.destroy</tt>. Хосту с
      # soft-delete-гемом достаточно переопределить на <tt>resource.discard</tt>.
      def remove_resource(resource)
        resource.destroy
      end

      private

      def attempt_removal(resource)
        remove_resource(resource) ? Success(resource) : Failure(resource)
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
