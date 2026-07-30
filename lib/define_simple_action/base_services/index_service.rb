# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Пагинация (<tt>limit</tt>/<tt>limitless</tt>/<tt>offset</tt>) + сборка ответа через
    # #build_response. Никакой фильтрации/сортировки по умолчанию — #prepare_query просто
    # <tt>scope(params)</tt>, без <tt>#ransack</tt> и любой другой query-библиотеки.
    class IndexService < BaseService
      # Принимает <tt>params</tt> с ключами <tt>limit:</tt>/<tt>limitless:</tt>/<tt>offset:</tt>
      # (плюс всё, что нужно переопределённому #prepare_query) и всегда возвращает Success —
      # сама по себе выборка не падает с Failure.
      def execute(params = {})
        Success(build_response(paginate(params)))
      end

      protected

      # Единая точка расширения вместо трёх (transform_result/response_class/сборка
      # ответа): хосту, которому нужен свой класс ответа и/или трансформация resource,
      # достаточно переопределить build_response целиком (обычно вызвав super с уже
      # трансформированным pagination[:resource]) — никакого отдельного
      # call_hook(:index_response_class, ...).
      def build_response(pagination)
        ::DefineSimpleAction::BaseServices::Responses::IndexResponse.new(
          data: pagination[:resource],
          meta: pagination.slice(:count, :limit, :offset)
        )
      end

      # Дефолт без фильтрации: gem не знает про Ransack. Хосту, которому нужна
      # query-string фильтрация (q[title_cont]=... и т.д.), стоит либо переопределить
      # этот метод в конкретном сервисе, либо примонкипатчить его на весь IndexService
      # (см. README — "ActiveRecord/ransack/discard как монкипатч хоста").
      def prepare_query(params)
        scope(params)
      end

      # Список колонок для <tt>.select(...)</tt> — <tt>nil</tt> означает без ограничения
      # (весь набор колонок модели).
      def select_fields
        nil
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

      def paginate(params)
        limitless, limit, offset = limit_and_offset(params)
        query = prepare_query(params)
        resource = query.limit(limit).offset(offset)
        resource = resource.select(select_fields) if select_fields
        count = query.size

        { resource:, count:, limit: limitless ? count : limit, offset: }
      end
    end
  end
end
