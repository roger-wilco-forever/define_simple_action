# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    # DSL уровня класса, которым домешивается <tt>.define_simple_actions</tt> в контроллер,
    # включивший Concern (см. <tt>Concern.included</tt>).
    module ClassMethods
      # Создаёт action, если он не определён в классе
      #
      # * <tt>:actions</tt> — список необходимых actions, например <code>%i[index show create update destroy]</code>
      # * <tt>:model_name</tt> — имя модели (или класс), передаётся в сервис
      # * <tt>:response_formats</tt> — форматы ответа, например <code>%i[json csv]</code>
      # * <tt>**options</tt> — что угодно ещё (<tt>use_cache:</tt>, <tt>cache_expires_in:</tt>,
      #   <tt>notify_data:</tt> и т.д.) — gem эти имена не знает и не интерпретирует, просто
      #   прокидывает весь хэш как есть в #around_action_execution (см. Dispatch) и в
      #   конструктор сервиса (см. Resolution#fetch_service_for_action) — интерпретация
      #   целиком на стороне хоста.
      def define_simple_actions(actions:, model_name: nil, response_formats: DEFAULT_RESPONSE_FORMATS, **options)
        actions.map(&:to_sym).each do |action|
          next if method_defined?(action)

          define_method(action) do
            define_simple_action(action.to_s, model_name, response_formats, options)
          end
        end
      end
    end
  end
end
