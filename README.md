# DefineSimpleAction

Concern для Rails-контроллеров, который динамически генерирует простые CRUD-actions
(`index`, `show`, `show_by_slug`, `create`, `update`, `destroy`, `batch_destroy`, а также
произвольные кастомные) по конвенции имён — резолвит сервис, контракт валидации и params
для каждого action'а, вызывает сервис и передаёт результат в сериализацию/рендер.

Gem сознательно не имеет мнения о том, чем сериализуется ответ, как кэшируется результат
и откуда берутся данные авторизации — это точки расширения (хуки), которые обязано
реализовать хост-приложение.

## Установка

Пока не публикуется в rubygems.org, подключается как git-зависимость:

```ruby
gem "define_simple_action", git: "https://github.com/Randewoo-Tech/define_simple_action.git"
```

## Быстрый старт

```ruby
class BrandsController < ApplicationController
  include DefineSimpleAction::Concern

  define_simple_actions(
    actions: %i[index show create update destroy],
    model_name: "Catalog::Brand"
  )

  private

  def resource_params
    params.require(:brand).permit(:title, :slug)
  end

  # --- обязательные хуки ---

  def authorization_data
    { current_user: current_user }
  end

  def serialize_for_action(name, result, service_params)
    return ErrorBlueprint.render(result) if result.failure?

    BrandBlueprint.render_as_json(result.value!)
  end
end
```

## Контракт с сервисным слоем

Сервис для action'а `foo` резолвится как `"#{prefix}::FooService"` (с опциональным
фоллбэком через `fallback_service_namespace`, см. ниже) и инстанцируется с kwargs:

```ruby
SomeService.new(
  authorization_data: authorization_data,     # результат хука #authorization_data
  model: model_name,                          # строка или класс, переданный в define_simple_actions
  notify_data: notify_data,                   # то, что передали в define_simple_actions (см. ниже)
  validation_contract_name: "..."             # см. #fetch_validation_contract_name_for_action
)
```

`notify_data:` concern передаёт нейтрально (просто прокидывает то, что дали в
`define_simple_actions(notify_data: ...)`) и никак не интерпретирует. `BaseServices::BaseService`
тоже не объявляет `option :notify_data` и не знает про `notify` — это целиком зона хоста, см.
раздел "Notify — не в gem'е" ниже.

Сервис должен отвечать на `#call(params)`, возвращая объект с `#failure?` (контракт
Result/dry-monads: `Success`/`Failure`).

### Failure(type: ..., errors: ...) — тип ошибки, не hook

Ошибки, которые gem формирует сам (а не подставляет дефолт при отсутствии hook'а), несут
тип прямо в `Failure`, а не форматированный ответ:

- `BaseServices::BaseService#validate_params` — dry-validation контракт (см. `#contract`) не
  прошёл: `Failure(type: :contract_validation, errors: {...})`. `errors:` — это
  `error.errors.to_h` контракта, глубоко продублированный (`DefineSimpleAction.deep_dup`, без
  ActiveSupport) — dry-validation отдаёт замороженный `MessageSet#to_h`, и хост, который
  мутирует его на месте (например, camelCase-трансформер ключей в блюпринте), иначе ловит
  `FrozenError`.
- `Create`/`Update`/`DestroyService` — `resource.save`/`#update`/`#destroy` вернули `false`:
  `Failure(type: :invalid_record, errors: {...})`, `errors:` — `resource.errors.messages`
  (тоже `deep_dup`).
- `BatchDestroyService` — не все записи удалились: `Failure(type: :batch_destroy, errors: [...])`,
  `errors:` — массив `full_messages` неудалившихся записей.

Это **не** `call_hook`-точки расширения — gem не вызывает никакой хостовый метод для
форматирования этих ошибок и не знает, во что они должны превратиться в ответе (код ошибки,
конверт и т.д.). Матчинг по `:type` и перевод в конкретный формат ответа — целиком на хосте,
в точке, где он рендерит `Failure` (например, `serialize_for_action` в
`DefineSimpleAction::Concern`), а не на уровне сервиса:

```ruby
def serialize_for_action(name, result, service_params)
  return render_error(result) if result.failure?
  ...
end

FAILURE_TYPE_TO_CODE = { contract_validation: "VALIDATION_ERROR", invalid_record: "ACTIVE_RECORD_ERROR",
                         batch_destroy: "ACTIVE_RECORD_ERROR" }.freeze

def render_error(result)
  failure = result.failure
  code = failure.is_a?(Hash) && FAILURE_TYPE_TO_CODE[failure[:type]]

  code ? ErrorPresenter.build(code:, messages: failure[:errors]) : failure
end
```

## Точки расширения (хуки)

Обязательные (по умолчанию — `NotImplementedError`):

- `authorization_data` — данные авторизации, передаются в сервис.
- `serialize_for_action(name, result, service_params)` — превращает результат сервиса
  в тело ответа. Gem намеренно не привязан к конкретному сериализатору (Blueprinter,
  Jbuilder, ActiveModel::Serializer — что угодно).

Опциональные (есть дефолт, который можно переопределить):

- `around_action_execution(**opts) { ... }` — оборачивает вызов сервиса + сериализацию;
  сюда попадают `name:`, `model_name:`, `service_params:`, `use_cache:`, `cache_expires_in:`
  из вызова `define_simple_actions`/`define_simple_action`. Дефолт — просто `yield`.
  Используется, например, для кэширования результата.
- `fallback_service_namespace` — неймспейс, куда падает резолвинг сервиса, если
  `"#{prefix}::FooService"` не существует. Дефолт — `nil` (фоллбэка нет, `NameError`
  пробрасывается наружу).
- `make_response_#{format}` — рендер конкретного формата ответа. Из коробки есть только
  `make_response_json`. Для дополнительных форматов (например, `csv`) добавьте свой
  `make_response_csv` и передайте `response_formats: %i[json csv]`.

## Переопределяемые методы (по конвенции, без объявления хуков)

- `fetch_params_for_#{action}` / `resource_params` / `resource_#{action}_params` - параметры для action'а.
- `fetch_service_for_#{action}` - полностью кастомный сервис для action'а.
- `fetch_status_for_#{action}` - кастомный HTTP-статус.
- `validation_contract_name_for_#{action}` - явное имя контракта валидации.
- `prefix` - переопределяется константой `PREFIX` в контроллере, иначе берётся из
  имени класса.

## BaseServices

`DefineSimpleAction::BaseServices` — сервисный слой, под который резолвит `fetch_service_for_action`:
`Index`, `Show`, `ShowBySlug`, `Create`, `Update`, `Destroy`, `BatchDestroyService`, плюс общий
`BaseService` (dry-monads/dry-initializer, резолвинг validation-контракта по имени класса).

```ruby
class BrandsController::IndexService < DefineSimpleAction::BaseServices::IndexService
end
```

### Хуки — динамические, не декларируются в gem'е

В отличие от `authorization_data`/`serialize_for_action` в `Concern` (обязательные, с
`NotImplementedError` по умолчанию), хуки `BaseServices` **не существуют как методы**, пока
хост их не определит. Внутри gem'а на каждой точке расширения вызывается:

```ruby
call_hook(:some_hook_name, *args) # => __send__(:some_hook_name, *args), если respond_to?, иначе nil
```

а конкретное поведение по умолчанию подставляется на месте вызова через `||`. Хост создаёт
только те хуки, которые ему реально нужны в его ситуации — ничего не обязательно
переопределять заранее и нечего "затирать" пустой реализацией.

Сам gem `call_hook` больше никуда изнутри не зовёт — ни одной точки расширения на его
дефолтные имена (`index_response_class`, `soft_delete?`, `after_mutation`, `notify`) в коде
gem'а не осталось, см. разделы "IndexService#build_response — не hook", "Удаление — не hook",
"after_mutation — не в gem'е" и "Notify — не в gem'е" ниже — все они теперь либо обычные
переопределяемые методы, либо `after_execute`. `call_hook` остаётся публичным методом
`BaseService` как готовый примитив для **собственных** точек расширения хоста (пример — вызов
`notify` из host-side `Notifiable`-модуля в разделе "Notify — не в gem'е").

### Удаление — не hook, обычный переопределяемый метод

Раньше `Destroy`/`BatchDestroyService` сами звали `call_hook(:soft_delete?, model_class)` и по
результату выбирали `:discard`/`:destroy` (`:discard_all`/`:destroy_all`) — то есть gem знал имена
методов стороннего гема `discard`. Теперь это обычное переопределение метода, без hook и без
привязки к конкретному soft-delete-гему:

- `DestroyService#remove_resource(resource)` — дефолт `resource.destroy`.
- `BatchDestroyService#remove_resources(relation)` / `#removed?(resource)` — дефолт
  `relation.destroy_all` / `resource.destroyed?`.

```ruby
class BrandsController::DestroyService < DefineSimpleAction::BaseServices::DestroyService
  protected

  def remove_resource(resource)
    resource.discard
  end
end

class BrandsController::BatchDestroyService < DefineSimpleAction::BaseServices::BatchDestroyService
  protected

  def remove_resources(relation)
    relation.discard_all
  end

  def removed?(resource)
    resource.discarded?
  end
end
```

### IndexService#build_response — не hook, обычный переопределяемый метод

Раньше в `IndexService#execute` было три отдельных места: `transform_result` (трансформация
`resource` через do-нотацию), `call_hook(:index_response_class)` (выбор класса ответа) и
инлайновая сборка `{data:, meta:}`. Теперь это один переопределяемый метод —
`build_response(pagination)`, где `pagination` — хэш `{resource:, count:, limit:, offset:}` из
`#paginate`. Дефолт:

```ruby
def build_response(pagination)
  DefineSimpleAction::BaseServices::Responses::IndexResponse.new(
    data: pagination[:resource],
    meta: pagination.slice(:count, :limit, :offset)
  )
end
```

Хосту, которому нужен свой класс ответа и/или трансформация `resource`, достаточно
переопределить `build_response` целиком — трансформировать `pagination[:resource]` и вызвать
`super` с уже готовым классом/результатом:

```ruby
class ApplicationService::Index < DefineSimpleAction::BaseServices::IndexService
  protected

  def build_response(pagination)
    ApplicationService::Responses::IndexResponse.new(
      data: pagination[:resource],
      meta: pagination.slice(:count, :limit, :offset)
    )
  end
end

class BrandsController::IndexService < ApplicationService::Index
  protected

  def build_response(pagination)
    super(pagination.merge(resource: pagination[:resource].map { |r| BrandEntity.new(r) }))
  end
end
```

### before_execute / after_execute — Rails-подобные callback-цепочки

В отличие от `call_hook` (один опциональный метод на точку расширения), `before_execute`/
`after_execute` — полноценные цепочки: можно повесить несколько callback'ов на одну и ту же
точку (в т.ч. из разных модулей, подключённых в один сервис), с условиями `if:`/`unless:`,
и они наследуются (подкласс добавляет свои, не трогая родительские):

```ruby
class BrandsController::CreateService < DefineSimpleAction::BaseServices::CreateService
  before_execute :authorize_brand!
  before_execute :normalize_slug, if: :slug_present?
  after_execute :invalidate_cache

  def authorize_brand!(_params)
    Failure(errors: ["forbidden"]) unless current_user.admin?
  end

  def normalize_slug(_params)
    # ...
  end

  def slug_present?(params)
    params[:slug].present?
  end

  def invalidate_cache(result)
    Rails.cache.delete("brands") if result.success?
  end
end
```

Callback можно задать именем метода (символ, можно несколько за один вызов) или блоком
(`before_execute { ... }`, `instance_exec`'ится на сервисе).

`before_execute`-callback (и его `if:`/`unless:`-guard) получает аргументом `service_params` —
те же params, что переданы в `#call`; `after_execute`-callback (и его guard) — финальный
`Result` из `#execute`. Оба передаются явно, а не через скрытое состояние сервиса; если
`after_execute` нужен только на успех, проверяйте `result.success?` внутри колбэка или в
guard'е (`if: ->(result) { result.success? }`).

Остановка цепочки — через dry-monads, а не Rails-овский `throw(:abort)`: если
`before_execute`-callback возвращает `Failure(...)`, она становится результатом `#call`,
а `#execute` и все остальные `before_execute`/`after_execute` не вызываются. `after_execute`
запускается всегда после `#execute` (успех или неудача) — сам колбэк ничего не подменяет,
чисто побочный эффект.

### after_mutation — не в gem'е

Раньше `Create`/`Update`/`BatchDestroyService` сами звали `call_hook(:after_mutation, model.name)`
на успехе. Теперь gem этого не делает вообще — как и с `notify` (см. ниже), это чистый побочный
эффект без формата ответа, и `after_execute` — прямая замена: колбэк получает финальный `Result`,
`if: ->(result) { result.success? }` воспроизводит прежнее "только на успех":

```ruby
class ApplicationService::Create < DefineSimpleAction::BaseServices::CreateService
  after_execute :invalidate_cache, if: ->(result) { result.success? }

  private

  def invalidate_cache(_result)
    Rails.cache.delete("brands")
  end
end
```

### Notify — не в gem'е

`notify`/`notify_data` были в gem'е как готовый хук с конвенцией `watch_keys` — теперь это
целиком зона хоста, по той же логике, что и ActiveRecord/Ransack/discard (см. ниже): concern
нейтрально прокидывает `notify_data:` в `service_params` (host сам решает, что туда положить и
как назвать), а `BaseServices::BaseService` про `notify` вообще не знает — ни `option`, ни
вызова. Всё, что нужно для восстановления прежнего поведения, уже публично доступно
(`option`, `after_execute`, `call_hook`), monkeypatch/`prepend` не требуется — достаточно
обычного `include` в свой сервисный слой:

```ruby
# app/services/application_service/notifiable.rb (или где угодно у хоста)
module ApplicationService
  module Notifiable
    def self.included(base)
      base.option :notify_data, optional: true, reader: :private
      base.after_execute :dispatch_notify, if: :notify_applicable?
    end

    private

    def notify_applicable?(result)
      result.success? && notify_data&.dig(:watch_keys)&.any?
    end

    def dispatch_notify(result)
      call_hook(:notify, result.value!)
    end
  end
end

class ApplicationService::Base < DefineSimpleAction::BaseServices::BaseService
  include ApplicationService::Notifiable
end
```

Дальше в конкретном сервисе — как раньше:

```ruby
class BrandsController::CreateService < ApplicationService::Base
  def notify(resource)
    NotifyBrandChangeJob.perform_later(resource.id)
  end
end
```

### Инструментация — dry-monitor

Вокруг `#execute` всегда публикуется событие `define_simple_action.execute` через
`Dry::Monitor::Notifications` (`service:`, `model:`, `success:`, `time:` в наносекундах).
Подписка — целиком на хосте, gem ничего не решает за него:

```ruby
DefineSimpleAction.notifications.subscribe("define_simple_action.execute") do |event|
  StatsD.timing("services.#{event[:service]}", event[:time])
end
```

### Опасность бок о бок с Dry::Monads[:do]

`BaseService` подключает `Dry::Monads[:do]`, который **автоматически оборачивает в do-нотацию
каждый метод класса** (а не только `execute`/`call`). Внутри такого обёрнутого метода `yield`
и `block_given?` перехватываются do-machinery (которая ждёт монаду и вызывает `.to_monad` на
результате), а не блоком вызывающего — даже если вызывающий не передавал блок вовсе. Поэтому
`call_hook` **намеренно не принимает default-блок** (`{ ... }`/`&block`) — дефолт всегда
подставляется через `||` на месте вызова, а не через `yield` внутри `call_hook`.

## Зависимости

Gem не зависит от Rails/ActiveSupport — только dry-rb (`dry-monads`, `dry-initializer`,
`dry-types`, `dry-inflector`, `dry-transformer`, `dry-monitor`):

- `camelize`/`underscore` — `Dry::Inflector`, а не `ActiveSupport::Inflector`.
- `constantize`/`safe_constantize` — свои, `DefineSimpleAction.constantize`/`.safe_constantize`
  (обёртка над `Object#const_get`), а не ActiveSupport-монкипатч `String#constantize`.
- `deep_symbolize_keys` — `Dry::Transformer::HashTransformations.deep_symbolize_keys`, а не
  `Hash#deep_symbolize_keys`.
- `ActiveModel::Type::Boolean` — `Dry::Transformer::Coercions.to_boolean` (с `rescue KeyError`
  на нераспознанных значениях), а не `activemodel`.

`Concern` (контроллерный слой) остаётся Rails-специфичным по своей природе — он подмешивается
в `ActionController` и использует `params`/`request`/`render`/`respond_to` напрямую; это не
то, что имеет смысл абстрагировать.

## ActiveRecord/Ransack/discard — не в gem'е вообще

В отличие от v1 (где эти интеграции жили в gem'е как duck-typed рантайм-проверки), сейчас
`BaseServices` **вообще не знает** об ActiveRecord/Ransack/discard:

- `IndexService#prepare_query` по умолчанию — просто `scope(params)`, без вызова `#ransack`.
- `Create/Update/BatchDestroyService` не перехватывают вообще никаких исключений — что
  бы ни бросил `#create_resource`/`model.find`/`destroy_all`, оно пробрасывается наружу как есть.

Если хост использует ActiveRecord/Ransack/discard, это подключается монкипатчем
(`Module#prepend`) поверх классов gem'а — это код хоста, не gem'а:

```ruby
# config/initializers/define_simple_action_active_record.rb (или app/services/.../*.rb)
module ActiveRecordIndexQuery
  def prepare_query(params)
    scope(params).ransack(params[:q], auth_object: auth_object).result
  end
end

module ActiveRecordCreateErrorHandling
  def execute(params)
    super
  rescue ActiveRecord::RecordNotFound => e
    raise e
  rescue ActiveRecord::InvalidForeignKey => e
    Failure(foreign_key_error(e))
  rescue StandardError => e
    Failure(unexpected_error(e))
  end
end

DefineSimpleAction::BaseServices::IndexService.prepend(ActiveRecordIndexQuery)
DefineSimpleAction::BaseServices::CreateService.prepend(ActiveRecordCreateErrorHandling)
```

Важный нюанс: `Update`/`BatchDestroyService` в gem'е **не имеют собственного `rescue`**, так что
`prepend` с `rescue` вокруг `super` работает напрямую. `Create`/`BatchDestroyService`-специфичные
StandardError-перехватчики — то же самое, т.к. в gem'е теперь такого перехвата вообще нет (было
раньше, но убрано вместе с ActiveRecord-осведомлённостью). Если бы у метода в gem'е был свой
`rescue StandardError` — простой `prepend` + `rescue` вокруг `super` не сработал бы (внутренний
`rescue` перехватил бы исключение раньше, чем оно дошло бы до прикладного `rescue`); в этом случае
пришлось бы выносить перехват в отдельный переопределяемый метод. См. Randewoo
(`app/services/redesign/active_record_error_handling.rb`) за рабочим примером.

## Development

```bash
bin/setup
bundle exec rspec
```

## Roadmap

- v1 - 1:1 перенос механизма (текущая версия).
- v2 - декларативный DSL (`action_options:` с точечными переопределениями на action) -  см. проектную документацию.
