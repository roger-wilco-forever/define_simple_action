# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Типизированные контейнеры результатов сервисов (пока только IndexResponse).
    module Responses
      # Результат IndexService#execute на успехе — <tt>data</tt> (то, что вернул
      # #paginate/#build_response) и <tt>meta</tt> (<tt>count</tt>/<tt>limit</tt>/<tt>offset</tt>,
      # все типизированы как целые числа). Никакой сериализации в себе не несёт — это
      # просто типизированный контейнер, который дальше рендерит хост (см. Concern#render_resource).
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
