# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    module Responses
      class IndexResponse
        extend Dry::Initializer

        option :data

        option :meta do
          option :count, Dry::Types['strict.integer']
          option :limit, Dry::Types['strict.integer']
          option :offset, Dry::Types['strict.integer']
        end
      end
    end
  end
end
