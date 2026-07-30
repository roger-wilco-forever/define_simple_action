# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    # Дефолтные <tt>resource_#{action}_params</tt> по конвенции CRUD_ACTION_DATA
    # (ransack-совместимый index/show, deep_symbolize_keys вместо ActiveSupport).
    module ResourceParams
      def default_ordering
        "id asc"
      end

      def compacted_ransack_params(params)
        ransack_params = (params[:q] || {}).to_enum&.to_h
        deep_symbolize_keys(ransack_params)&.compact
      end

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
        q = compacted_ransack_params(params)
        q[:s] ||= default_ordering if default_ordering

        {
          limit: params[:limit],
          limitless: params[:limitless],
          offset: params[:offset],
          q:
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
