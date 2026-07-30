# frozen_string_literal: true

module DefineSimpleAction
  module SerializationConcern
    # Резолвинг класса-сериализатора по конвенции имён (как Concern::Resolution резолвит сервис).
    module Resolution
      # Класс-сериализатор для action'а. Определяется:
      # * в контроллере <tt>set_serializer_name_for_#{name}</tt> — возвращает имя класса строкой
      # * в контроллере <tt>default_serializer_name</tt> — определяет класс напрямую для всех action'ов
      # * иначе конвенция <tt>"#{prefix}::#{name.camelize}Serializer"</tt>
      def fetch_serializer_class_for_action(name)
        method_name = :"set_serializer_name_for_#{name}"
        serializer_name = respond_to?(method_name, true) ? __send__(method_name) : default_serializer_name(name)

        ::DefineSimpleAction.constantize(serializer_name)
      end

      def default_serializer_name(name)
        "#{prefix}::#{::DefineSimpleAction::INFLECTOR.camelize(name)}Serializer"
      end
    end
  end
end
