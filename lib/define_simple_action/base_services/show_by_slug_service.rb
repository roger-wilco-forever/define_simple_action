# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # То же самое, что ShowService, но резолвит ресурс по <tt>params[:slug]</tt>
    # (<tt>scope(params).find_by!(slug: ...)</tt>) вместо <tt>params[:id]</tt>.
    class ShowBySlugService < BaseService
      # Находит ресурс по <tt>params[:slug]</tt> и всегда возвращает Success.
      def execute(params)
        resource = scope(params).find_by!(slug: params[:slug])

        Success(resource)
      end
    end
  end
end
