# frozen_string_literal: true

require_relative "serialization_concern/hooks"
require_relative "serialization_concern/resolution"
require_relative "serialization_concern/dispatch"

# Дефолтная реализация Concern#serialize_for_action — резолвинг класса-сериализатора по
# конвенции имён (как fetch_service_for_action резолвит сервис) плюс диспетчеризация
# success/failure. Опционально: подключается вместе с DefineSimpleAction::Concern, ничего не
# меняет автоматически — сам Concern по-прежнему требует serialize_for_action на любом хосте,
# который не подключил этот модуль.
#
# Единственное место, которое знает о конкретной библиотеке сериализации — #render_resource.
# Gem не зависит ни от Blueprinter, ни от любой другой — см. SerializationConcern::Hooks.
#
# Формат ошибок gem не решает вообще (см. README, "Failure(type: ..., errors: ...) — тип
# ошибки, не hook") — #render_error обязателен к переопределению, как и authorization_data/
# serialize_for_action в самом Concern.
#
# Реализация разложена по под-модулям (все подмешиваются сюда же, ничего не меняется для
# хоста — как включал <tt>DefineSimpleAction::SerializationConcern</tt>, так и продолжает):
# * SerializationConcern::Hooks — точки расширения (render_resource/render_error/
#   serializer_options/encode_response)
# * SerializationConcern::Resolution — резолвинг класса-сериализатора по конвенции имён
# * SerializationConcern::Dispatch — сама точка входа, #serialize_for_action
module DefineSimpleAction
  module SerializationConcern
    include Hooks
    include Resolution
    include Dispatch
  end
end
