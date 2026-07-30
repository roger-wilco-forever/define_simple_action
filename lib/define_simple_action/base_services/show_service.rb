# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # <tt>scope(params).find(params[:id])</tt> — ничего сверх этого. Не перехватывает
    # <tt>RecordNotFound</tt> (или что бросит переопределённый #scope) — оно пробрасывается
    # наружу как есть, обработка целиком на хосте.
    class ShowService < BaseService
      # Находит ресурс по <tt>params[:id]</tt> и всегда возвращает Success — сам поиск
      # ничего не оборачивает в Failure (см. класс-комментарий выше).
      def execute(params)
        resource = scope(params).find(params[:id])

        Success(resource)
      end
    end
  end
end
