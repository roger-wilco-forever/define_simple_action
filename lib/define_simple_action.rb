# frozen_string_literal: true

require 'active_support/core_ext/enumerable'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'

require_relative 'define_simple_action/version'
require_relative 'define_simple_action/concern'
require_relative 'define_simple_action/base_services'

module DefineSimpleAction
  class Error < StandardError; end
end
