# frozen_string_literal: true

require 'json'

# Дефолтная реализация Concern#serialize_for_action — резолвинг класса-сериализатора по
# конвенции имён (как fetch_service_for_action резолвит сервис) плюс диспетчеризация
# success/failure. Опционально: подключается вместе с DefineSimpleAction::Concern, ничего не
# меняет автоматически — сам Concern по-прежнему требует serialize_for_action на любом хосте,
# который не подключил этот модуль.
#
# Форма ответа ({data:, meta:} для index, {data: [id, ...]} для batch_destroy или что угодно
# ещё) — целиком зона сериализатора, а не gem'а: gem резолвит класс по имени action'а и
# передаёт ему "сырое" значение результата (result.value!) как есть — IndexResponse
# (data:/meta:) для index, массив снятых записей для batch_destroy, ресурс для остального.
# Собрать финальный хэш ответа — дело конкретного Widgets::IndexSerializer/BatchDestroySerializer,
# gem в это не вмешивается.
#
# Единственное место, которое знает о конкретной библиотеке сериализации — #render_resource.
# Gem не зависит ни от Blueprinter, ни от любой другой — дефолт ожидает интерфейс
# #call(object, options), которому Blueprinter/ActiveModel::Serializer/Jbuilder не
# соответствуют "из коробки". Замена библиотеки — переопределение одного этого метода,
# а не переписывание каждого конкретного сериализатора:
#
#   def render_resource(serializer_class, object, options)
#     serializer_class.render_as_json(object, options) # Blueprinter
#   end
#
# Формат ошибок gem не решает вообще (см. README, "Failure(type: ..., errors: ...) — тип
# ошибки, не hook") — #render_error обязателен к переопределению, как и authorization_data/
# serialize_for_action в самом Concern.
module DefineSimpleAction
  module SerializationConcern
    def serialize_for_action(name, result, service_params)
      method_name = :"fetch_serializer_for_#{name}"
      return __send__(method_name, result, service_params) if respond_to?(method_name, true)

      options = serializer_options(name, service_params)

      return encode_response(render_error(result.failure, options)) if result.failure?
      return if name == ::DefineSimpleAction::Concern::ACTION_DESTROY

      encode_response(render_resource(fetch_serializer_class_for_action(name), result.value!, options))
    end

    protected

    # Единственная точка, которая знает о конкретной библиотеке сериализации — см. заголовок файла.
    def render_resource(serializer_class, object, options)
      serializer_class.call(object, options)
    end

    # Формат ошибок — целиком зона хоста, gem не имеет мнения (см. заголовок файла).
    def render_error(_failure, _options)
      raise NotImplementedError, "#{self.class} must implement #render_error"
    end

    # Класс-сериализатор для action'а. Определяется:
    # * в контроллере <tt>set_serializer_name_for_#{name}</tt> — возвращает имя класса строкой
    # * иначе конвенция <tt>"#{prefix}::#{name.camelize}Serializer"</tt>
    def fetch_serializer_class_for_action(name)
      method_name = :"set_serializer_name_for_#{name}"
      serializer_name = respond_to?(method_name, true) ? __send__(method_name) : default_serializer_name(name)

      ::DefineSimpleAction.constantize(serializer_name)
    end

    def default_serializer_name(name)
      "#{prefix}::#{::DefineSimpleAction::INFLECTOR.camelize(name)}Serializer"
    end

    def serializer_options(_name, _service_params)
      {}
    end

    def encode_response(hash)
      ::JSON.generate(hash)
    end
  end
end
