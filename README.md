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
  notify_data: notify_data,                   # то, что передали в define_simple_actions
  validation_contract_name: "..."             # см. #fetch_validation_contract_name_for_action
)
```

Сервис должен отвечать на `#call(params)`, возвращая объект с `#failure?` (контракт
Result/dry-monads: `Success`/`Failure`).

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

## Development

```bash
bin/setup
bundle exec rspec
```

## Roadmap

- v1 - 1:1 перенос механизма (текущая версия).
- v2 - декларативный DSL (`action_options:` с точечными переопределениями на action) -  см. проектную документацию.
