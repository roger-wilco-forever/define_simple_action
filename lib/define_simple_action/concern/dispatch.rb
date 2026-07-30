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

      def fetch_serialized_result_and_status(name, model_name, service_params, notify_data)
        result = fetch_service_for_action(name, model_name, notify_data).call(service_params)

        [serialize_for_action(name, result, service_params), fetch_status_for_action(name, result)]
      end
    end
  end
end
