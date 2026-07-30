# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    module ClassMethods
      # Создаёт action, если он не определён в классе
      #
      # * <tt>:actions</tt> — список необходимых actions, например <code>%i[index show create update destroy]</code>
      # * <tt>:model_name</tt> — имя модели (или класс), передаётся в сервис
      # * <tt>:use_cache</tt> — включить кэш (интерпретируется в <tt>around_action_execution</tt> хоста)
      # * <tt>:cache_expires_in</tt> — TTL кэша (интерпретируется хостом, gem значения не задаёт)
      # * <tt>:response_formats</tt> — форматы ответа, например <code>%i[json csv]</code>
      # * <tt>:notify_data</tt> — произвольные данные, прокидываются в сервис как есть
      def define_simple_actions( # rubocop:disable Metrics/ParameterLists
        actions:,
        model_name: nil,
        use_cache: false,
        cache_expires_in: nil,
        response_formats: DEFAULT_RESPONSE_FORMATS,
        notify_data: nil
      )
        actions.map(&:to_sym).each do |action|
          next if method_defined?(action)

          define_method(action) do
            define_simple_action(
              action.to_s, model_name, response_formats, notify_data, use_cache, cache_expires_in
            )
          end
        end
      end
    end
  end
end
