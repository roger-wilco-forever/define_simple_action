# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class ShowBySlugService < BaseService
      def execute(params)
        resource = scope(params).find_by!(slug: params[:slug])

        Success(resource)
      end
    end
  end
end
