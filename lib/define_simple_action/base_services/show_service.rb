# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class ShowService < BaseService
      def execute(params)
        resource = scope(params).find(params[:id])

        Success(resource)
      end
    end
  end
end
