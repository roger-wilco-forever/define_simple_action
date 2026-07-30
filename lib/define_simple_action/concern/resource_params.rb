# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    # Дефолтные <tt>resource_#{action}_params</tt> по конвенции CRUD_ACTION_DATA
    # (deep_symbolize_keys вместо ActiveSupport). Никакого Ransack — как и в BaseServices
    # (см. README, "ActiveRecord/Ransack/discard — не в gem'е вообще"): <tt>q:</tt> здесь —
    # нейтральный контейнер для произвольных query-параметров, который gem просто
    # прокидывает дальше символизированным, не придавая ему ransack-семантики (сортировка,
    # `.ransack(...)` и т.д. — целиком дело хоста, как и `prepare_query` в IndexService).
    module ResourceParams
      def resource_batch_destroy_params
        { ids: params[:ids] }
      end

      def resource_create_params
        resource_params
      end

      def resource_destroy_params
        { id: Integer(params[:id]) }
      end

      def resource_index_params
        {
          limit: params[:limit],
          limitless: params[:limitless],
          offset: params[:offset],
          q: deep_symbolize_keys(params[:q]&.to_unsafe_h)
        }.compact
      end

      def resource_show_by_slug_params
        {
          q: deep_symbolize_keys(params[:q]&.to_unsafe_h),
          slug: params[:slug]
        }.compact
      end

      def resource_show_params
        {
          id: Integer(params[:id]),
          q: deep_symbolize_keys(params[:q]&.to_unsafe_h)
        }.compact
      end

      def resource_update_params
        resource_params.merge(id: Integer(params[:id]))
      end

      # dry-transformer вместо ActiveSupport Hash#deep_symbolize_keys; сам метод не
      # принимает nil, поэтому оборачиваем (params[:q] нередко отсутствует).
      def deep_symbolize_keys(value)
        return value if value.nil?

        ::Dry::Transformer::HashTransformations.deep_symbolize_keys(value)
      end
    end
  end
end
