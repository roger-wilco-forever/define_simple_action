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
      def execute(params)
        resource = destroy_resource(params)

        if remove_resource(resource)
          Success(resource)
        else
          Failure(type: :invalid_record, errors: ::DefineSimpleAction.deep_dup(resource.errors.messages))
        end
      end

      protected

      # Для возможности переопределить этот кусок кода в дочерних классах
      def destroy_resource(params)
        @destroy_resource ||= scope(params).find(params[:id])
      end

      def remove_resource(resource)
        resource.destroy
      end
    end
  end
end
