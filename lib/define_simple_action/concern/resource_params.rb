# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    # Дефолтные <tt>resource_#{action}_params</tt> по конвенции CRUD_ACTION_DATA. Никакого
    # <tt>q:</tt>/Ransack — как и в BaseServices (см. README, "ActiveRecord/Ransack/discard —
    # не в gem'е вообще"): ни один сервис gem'а не читает <tt>params[:q]</tt> сам
    # (`IndexService#prepare_query`/`ShowService#execute`/`ShowBySlugService#execute` —
    # обычный `scope(params)`/`find`, без `.ransack`), так что строить и прокидывать
    # <tt>q:</tt> здесь незачем — хост, которому нужен фильтр/сортировка/ассоциации,
    # добавляет свой <tt>q:</tt> в собственном override (см. README).
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
          offset: params[:offset]
        }.compact
      end

      def resource_show_by_slug_params
        { slug: params[:slug] }.compact
      end

      def resource_show_params
        { id: Integer(params[:id]) }
      end

      def resource_update_params
        resource_params.merge(id: Integer(params[:id]))
      end
    end
  end
end
