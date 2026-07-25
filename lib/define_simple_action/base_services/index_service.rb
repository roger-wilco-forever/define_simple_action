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

        Success(
          ::DefineSimpleAction::BaseServices::Responses::IndexResponse.new(
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

      # Резолвится Ransack'ом как auth_object при вызове #ransack — реализация,
      # завязанная на конкретный класс админ-пользователя, должна жить в хосте.
      def auth_object
        nil
      end

      def limit_and_offset(params)
        limitless = ActiveModel::Type::Boolean.new.cast(params[:limitless])
        limit = limitless ? nil : (params[:limit] || self.class::PAGE_LENGTH).to_i
        offset = params[:offset].to_i
        [limitless, limit, offset]
      end

      def prepare_query(params)
        scope(params).ransack(params[:q], auth_object:).result
      end

      def select_fields
        nil
      end
    end
  end
end
