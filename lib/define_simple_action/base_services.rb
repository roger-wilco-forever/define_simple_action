# frozen_string_literal: true

require "dry/monads"
require "dry/initializer"
require "dry/types"

# ActiveRecord/ransack/discard НЕ требуются gem'ом — это опциональные интеграции хоста.
# Дефолтный IndexService ожидает от model/scope AR-подобный интерфейс (#ransack, #limit,
# #offset, #select, #size), а Create/Update/BatchDestroyService duck-type-проверяют
# конкретные классы исключений через DefineSimpleAction.safe_constantize в рантайме
# (см. BaseService#optional_error?) — без require и без записи в gemspec-зависимости.

require_relative "base_services/responses/index_response"
require_relative "base_services/base_service"
require_relative "base_services/index_service"
require_relative "base_services/show_service"
require_relative "base_services/show_by_slug_service"
require_relative "base_services/create_service"
require_relative "base_services/update_service"
require_relative "base_services/destroy_service"
require_relative "base_services/batch_destroy_service"

module DefineSimpleAction
  module BaseServices
  end
end
