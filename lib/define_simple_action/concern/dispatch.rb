# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    # Механизм диспетчеризации action'а: формат → params → сервис → сериализация → рендер.
    module Dispatch
      # === Дефолтный (JSON) рендер ответа. Для остальных форматов хост добавляет свой
      # <tt>make_response_#{format}</tt>. ===
      def make_response_json(format, serialized_result, status)
        format.json { render json: serialized_result, status: }
      end

      # Точка входа, на которую ссылаются action-методы, определённые ClassMethods#define_simple_actions.
      # 406 (<tt>:not_acceptable</tt>), если формат запроса не в <tt>response_formats</tt>;
      # иначе — params → сервис+сериализация (обёрнутые в #around_action_execution) → рендер
      # через <tt>make_response_#{format}</tt> для каждого запрошенного формата.
      def define_simple_action(name, model_name, response_formats, notify_data, use_cache, cache_expires_in) # rubocop:disable Metrics/ParameterLists
        return head :not_acceptable unless response_formats.include?(request.format.symbol)

        service_params = fetch_params_for_action(name)

        serialized_result, status = around_action_execution(
          name:, model_name:, service_params:, use_cache:, cache_expires_in:
        ) { fetch_serialized_result_and_status(name, model_name, service_params, notify_data) }

        respond_to do |format|
          response_formats.each do |response_format|
            public_send(:"make_response_#{response_format}", format, serialized_result, status)
          end
        end
      end

      # Резолвит и вызывает сервис (см. Resolution#fetch_service_for_action), затем
      # сериализует результат и резолвит HTTP-статус — пара <tt>[serialized_result, status]</tt>,
      # которую #define_simple_action передаёт в <tt>make_response_#{format}</tt>.
      def fetch_serialized_result_and_status(name, model_name, service_params, notify_data)
        result = fetch_service_for_action(name, model_name, notify_data).call(service_params)

        [serialize_for_action(name, result, service_params), fetch_status_for_action(name, result)]
      end

      # Дефолтная сериализация: резолвит класс-сериализатор по конвенции имён (как
      # fetch_service_for_action резолвит сервис) и рендерит через #render_resource/#render_error
      # (см. Hooks). Форма ответа ({data:, meta:} для index, {data: [id, ...]} для batch_destroy
      # или что угодно ещё) — целиком зона сериализатора, а не gem'а: gem передаёт ему "сырое"
      # значение результата (result.value!) как есть — IndexResponse (data:/meta:) для index,
      # массив снятых записей для batch_destroy, ресурс для остального. Полный обход всего
      # этого — <tt>fetch_serializer_for_#{name}</tt> в контроллере.
      def serialize_for_action(name, result, service_params)
        method_name = :"fetch_serializer_for_#{name}"
        return __send__(method_name, result, service_params) if respond_to?(method_name, true)

        options = serializer_options(name, service_params)

        return encode_response(render_error(result.failure, options)) if result.failure?
        return if name == ACTION_DESTROY

        encode_response(render_resource(fetch_serializer_class_for_action(name), result.value!, options))
      end
    end
  end
end
