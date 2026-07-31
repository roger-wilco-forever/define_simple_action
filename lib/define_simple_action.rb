# frozen_string_literal: true

require 'dry/inflector'
require 'dry/transformer'

require_relative 'define_simple_action/version'

# == DefineSimpleAction
#
# Concern для Rails-контроллеров, который динамически генерирует простые CRUD-actions
# (index/show/show_by_slug/create/update/destroy/batch_destroy, а также произвольные
# кастомные) по конвенции имён — резолвит сервис, контракт валидации, params и
# сериализатор для каждого action'а, вызывает сервис и рендерит результат.
#
# Не зависит от Rails/ActiveSupport (только dry-rb: dry-monads/dry-initializer/dry-types/
# dry-inflector/dry-transformer/dry-monitor) и не имеет мнения о том, какой библиотекой
# сериализуется ответ, где хранятся данные и как получается авторизация — это точки
# расширения (хуки), которые реализует хост. Два основных модуля:
#
# * DefineSimpleAction::Concern — контроллерный слой: <tt>define_simple_actions</tt>,
#   резолвинг сервиса/контракта/params/сериализатора по конвенции имён, дефолтная
#   диспетчеризация success/failure.
# * DefineSimpleAction::BaseServices — сервисный слой: <tt>Index</tt>/<tt>Show</tt>/
#   <tt>ShowBySlug</tt>/<tt>Create</tt>/<tt>Update</tt>/<tt>Destroy</tt>/<tt>BatchDestroyService</tt>,
#   плюс <tt>before_execute</tt>/<tt>after_execute</tt>-колбэки и dry-monitor-инструментация.
#
# См. README за подробным описанием точек расширения и примерами.
module DefineSimpleAction
  # Базовый класс ошибок gem'а (пока не используется — зарезервирован под будущие
  # gem-специфичные исключения).
  class Error < StandardError; end

  # dry-inflector вместо ActiveSupport::Inflector — camelize/underscore для резолвинга
  # сервисов/сериализаторов/контрактов по конвенции имён (см. Concern::Resolution).
  INFLECTOR = Dry::Inflector.new

  # Небольшая обёртка над Object#const_get вместо ActiveSupport#constantize —
  # единственный кусок инфлектора, которого нет в dry-inflector (он трансформирует
  # строки, но не резолвит константы).
  def self.constantize(name)
    Object.const_get(name.sub(/\A::/, ''))
  end

  # То же самое, что .constantize, но <tt>nil</tt> вместо NameError на несуществующей константе.
  def self.safe_constantize(name)
    constantize(name)
  rescue NameError
    nil
  end

  # Без ActiveSupport#deep_dup: дефолтная dry-validation-ошибка (см. BaseService#validate_params)
  # приходит с замороженными вложенными Hash — если хост (Blueprinter camelCase-трансформер
  # и т.п.) попробует мутировать её на месте, ловит FrozenError. Marshal round-trip вместо
  # ручной рекурсии — вызывается только на Hash/Array/String/Symbol (errors.messages/to_h),
  # всё это Marshal-совместимо.
  def self.deep_dup(value)
    Marshal.load(Marshal.dump(value))
  end
end

require_relative 'define_simple_action/concern'
require_relative 'define_simple_action/base_services'
