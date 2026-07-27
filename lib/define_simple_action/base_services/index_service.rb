# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class IndexService < BaseService
      def execute(params = {})
        limitless, limit, offset = limit_and_offset(params)

        query = prepare_query(params)
        resource = query.limit(limit).offset(offset)
        resource = resource.select(select_fields) if select_fields
        count = query.size

        resource = yield(transform_result(resource))

        response_class = call_hook(:index_response_class) || ::DefineSimpleAction::BaseServices::Responses::IndexResponse

        Success(
          response_class.new(
            data: resource,
            meta: {
              count:,
              limit: limitless ? count : limit,
              offset:
            }
          )
        )
      end

      private

      def cast_boolean(value)
        return false if value.nil?

        ::Dry::Transformer::Coercions.to_boolean(value)
      rescue KeyError
        false
      end

      def limit_and_offset(params)
        limitless = cast_boolean(params[:limitless])
        limit = limitless ? nil : (params[:limit] || self.class::PAGE_LENGTH).to_i
        offset = params[:offset].to_i
        [limitless, limit, offset]
      end

      # Дефолт без фильтрации: gem не знает про Ransack. Хосту, которому нужна
      # query-string фильтрация (q[title_cont]=... и т.д.), стоит либо переопределить
      # этот метод в конкретном сервисе, либо примонкипатчить его на весь IndexService
      # (см. README — "ActiveRecord/ransack/discard как монкипатч хоста").
      def prepare_query(params)
        scope(params)
      end

      def select_fields
        nil
      end
    end
  end
end
