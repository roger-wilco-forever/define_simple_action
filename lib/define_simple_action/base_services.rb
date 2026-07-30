# frozen_string_literal: true

require "dry/monads"
require "dry/initializer"
require "dry/types"

# ActiveRecord/ransack/discard НЕ требуются gem'ом — это опциональные интеграции хоста.
# Дефолтный IndexService ожидает от model/scope AR-подобный интерфейс (#limit, #offset,
# #select, #size), но не вызывает #ransack сам. Create/Update/Destroy/BatchDestroyService
# не перехватывают вообще никаких исключений — что бы ни бросил #create_resource/
# #update_resource/model.find/#destroy_all, оно пробрасывается наружу как есть; хост,
# которому нужен ActiveRecord-специфичный rescue, добавляет его сам через Module#prepend
# (см. README, "ActiveRecord/Ransack/discard — не в gem'е вообще").

require_relative "instrumentation"
require_relative "base_services/responses/index_response"
require_relative "base_services/callbacks"
require_relative "base_services/base_service"
require_relative "base_services/index_service"
require_relative "base_services/show_service"
require_relative "base_services/show_by_slug_service"
require_relative "base_services/create_service"
require_relative "base_services/update_service"
require_relative "base_services/destroy_service"
require_relative "base_services/batch_destroy_service"

module DefineSimpleAction
  # Сервисный слой, под который резолвит Concern#fetch_service_for_action: IndexService,
  # ShowService, ShowBySlugService, CreateService, UpdateService, DestroyService,
  # BatchDestroyService — плюс общий BaseService (dry-monads/dry-initializer,
  # резолвинг validation-контракта по имени класса, before_execute/after_execute-колбэки,
  # dry-monitor-инструментация).
  module BaseServices
  end
end
