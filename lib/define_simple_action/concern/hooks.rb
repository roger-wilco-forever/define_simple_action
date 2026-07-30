# frozen_string_literal: true

module DefineSimpleAction
  module Concern
    # Точки расширения хоста. Обязательные (#authorization_data, #serialize_for_action) —
    # NotImplementedError по умолчанию, хост должен их определить. Опциональные
    # (#around_action_execution, #fallback_service_namespace) — есть нейтральный дефолт.
    module Hooks
      # Данные авторизации, передаются в сервис как <tt>authorization_data:</tt>.
      def authorization_data
        raise NotImplementedError, "#{self.class} must implement #authorization_data"
      end

      # Оборачивает вызов сервиса + сериализацию (например, кэшем и/или APM-спаном).
      # Дефолт — без обёртки.
      def around_action_execution(**)
        yield
      end

      # Превращает результат сервиса в тело ответа. Обязателен к реализации на стороне хоста —
      # gem сознательно не имеет мнения о том, каким сериализатором пользуется приложение.
      def serialize_for_action(name, result, service_params)
        raise NotImplementedError, "#{self.class} must implement #serialize_for_action"
      end

      # Неймспейс базовых сервисов, используется как фоллбэк, если <tt>"#{prefix}::#{action}Service"</tt>
      # не существует. <tt>nil</tt> — фоллбэка нет, NameError пробрасывается наружу.
      def fallback_service_namespace
        nil
      end
    end
  end
end
