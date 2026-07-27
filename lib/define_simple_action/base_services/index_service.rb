# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    class IndexService < BaseService
      # Аналог ActiveModel::Type::Boolean::FALSE_VALUES — без зависимости от activemodel.
      FALSE_VALUES = [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF', ''].freeze

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
        return nil if value.nil?

        !FALSE_VALUES.include?(value)
      end

      def limit_and_offset(params)
        limitless = cast_boolean(params[:limitless])
        limit = limitless ? nil : (params[:limit] || self.class::PAGE_LENGTH).to_i
        offset = params[:offset].to_i
        [limitless, limit, offset]
      end

      def prepare_query(params)
        # auth_object резолвится Ransack'ом при вызове #ransack — реализация, завязанная
        # на конкретный класс админ-пользователя, должна жить в хосте (если вообще нужна).
        scope(params).ransack(params[:q], auth_object: call_hook(:auth_object)).result
      end

      def select_fields
        nil
      end
    end
  end
end
