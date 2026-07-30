# frozen_string_literal: true

module DefineSimpleAction
  module SerializationConcern
    # Механизм диспетчеризации: fetch_serializer_for_#{name}-обход → error/success → рендер → JSON.
    #
    # Форма ответа ({data:, meta:} для index, {data: [id, ...]} для batch_destroy или что угодно
    # ещё) — целиком зона сериализатора, а не gem'а: gem резолвит класс по имени action'а и
    # передаёт ему "сырое" значение результата (result.value!) как есть — IndexResponse
    # (data:/meta:) для index, массив снятых записей для batch_destroy, ресурс для остального.
    # Собрать финальный хэш ответа — дело конкретного Widgets::IndexSerializer/BatchDestroySerializer,
    # gem в это не вмешивается (см. Hooks#render_resource).
    module Dispatch
      def serialize_for_action(name, result, service_params)
        method_name = :"fetch_serializer_for_#{name}"
        return __send__(method_name, result, service_params) if respond_to?(method_name, true)

        options = serializer_options(name, service_params)

        return encode_response(render_error(result.failure, options)) if result.failure?
        return if name == ::DefineSimpleAction::Concern::ACTION_DESTROY

        encode_response(render_resource(fetch_serializer_class_for_action(name), result.value!, options))
      end
    end
  end
end
