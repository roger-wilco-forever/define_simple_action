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
      # Дефолт для <tt>batch_destroy</tt> — <tt>params[:ids]</tt> как есть.
      def resource_batch_destroy_params
        { ids: params[:ids] }
      end

      # Дефолт для <tt>create</tt> — делегирует хостовому #resource_params (единственный
      # метод, который gem всегда требует определить самому: разрешённые атрибуты
      # ресурса зависят от домена и не резолвятся по конвенции).
      def resource_create_params
        resource_params
      end

      # Дефолт для <tt>destroy</tt> — только <tt>id:</tt> из <tt>params[:id]</tt>.
      def resource_destroy_params
        { id: Integer(params[:id]) }
      end

      # Дефолт для <tt>index</tt> — <tt>limit:</tt>/<tt>limitless:</tt>/<tt>offset:</tt> как
      # есть. Без <tt>q:</tt> — ни один сервис gem'а сам <tt>params[:q]</tt> не читает
      # (см. README, "ActiveRecord/Ransack/discard — не в gem'е вообще").
      def resource_index_params
        {
          limit: params[:limit],
          limitless: params[:limitless],
          offset: params[:offset]
        }.compact
      end

      # Дефолт для <tt>show_by_slug</tt> — только <tt>slug:</tt> из <tt>params[:slug]</tt>.
      def resource_show_by_slug_params
        { slug: params[:slug] }.compact
      end

      # Дефолт для <tt>show</tt> — только <tt>id:</tt> из <tt>params[:id]</tt>.
      def resource_show_params
        { id: Integer(params[:id]) }
      end

      # Дефолт для <tt>update</tt> — #resource_params (см. #resource_create_params) плюс
      # <tt>id:</tt> из <tt>params[:id]</tt>.
      def resource_update_params
        resource_params.merge(id: Integer(params[:id]))
      end
    end
  end
end
