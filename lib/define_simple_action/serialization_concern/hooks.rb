# frozen_string_literal: true

require "json"

module DefineSimpleAction
  module SerializationConcern
    # Точки расширения хоста. Обязательная (#render_error) — NotImplementedError по
    # умолчанию, gem не решает формат конверта ошибки (см. README, "Failure(type: ...,
    # errors: ...) — тип ошибки, не hook"). Опциональные — есть нейтральный дефолт.
    module Hooks
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

      # Формат ошибок — целиком зона хоста, gem не имеет мнения.
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
