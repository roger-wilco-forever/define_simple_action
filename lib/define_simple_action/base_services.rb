# frozen_string_literal: true

require "dry/monads"
require "dry/initializer"
require "dry/types"
require "active_model"
require "active_record"
require "ransack"

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
