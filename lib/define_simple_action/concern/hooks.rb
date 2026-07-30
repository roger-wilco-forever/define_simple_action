# frozen_string_literal: true

require "json"

module DefineSimpleAction
  module Concern
    # Точки расширения хоста. Обязательные (#authorization_data, #render_error) —
    # NotImplementedError по умолчанию, хост должен их определить. Опциональные — есть
    # нейтральный дефолт. serialize_for_action сам по себе больше не hook — рабочий дефолт
    # (см. Dispatch#serialize_for_action) резолвит сериализатор по конвенции и рендерит через
    # #render_resource/#render_error ниже; переопределять сам serialize_for_action целиком
    # не нужно, если не требуется обойти весь механизм (см. fetch_serializer_for_#{name}).
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

      # Неймспейс базовых сервисов, используется как фоллбэк, если <tt>"#{prefix}::#{action}Service"</tt>
      # не существует. <tt>nil</tt> — фоллбэка нет, NameError пробрасывается наружу.
      def fallback_service_namespace
        nil
      end

      # Единственная точка, которая знает о конкретной библиотеке сериализации. Дефолт
      # ожидает интерфейс #call(object, options), которому Blueprinter/ActiveModel::Serializer/
      # Jbuilder не соответствуют "из коробки" — замена библиотеки это переопределение
      # ровно этого одного метода, а не переписывание каждого конкретного сериализатора:
      #
      #   def render_resource(serializer_class, object, options)
      #     serializer_class.render_as_json(object, options) # Blueprinter
      #   end
      def render_resource(serializer_class, object, options)
        serializer_class.call(object, options)
      end

      # Формат ошибок — целиком зона хоста, gem не имеет мнения (см. README, "Failure(type: ...,
      # errors: ...) — тип ошибки, не hook").
      def render_error(_failure, _options)
        raise NotImplementedError, "#{self.class} must implement #render_error"
      end

      def serializer_options(_name, _service_params)
        {}
      end

      def encode_response(hash)
        ::JSON.generate(hash)
      end
    end
  end
end
