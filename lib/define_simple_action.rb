# frozen_string_literal: true

require 'dry/inflector'

require_relative 'define_simple_action/version'

module DefineSimpleAction
  class Error < StandardError; end

  INFLECTOR = Dry::Inflector.new

  # Небольшая обёртка над Object#const_get вместо ActiveSupport#constantize —
  # единственный кусок инфлектора, которого нет в dry-inflector (он трансформирует
  # строки, но не резолвит константы).
  def self.constantize(name)
    Object.const_get(name.sub(/\A::/, ''))
  end

  def self.safe_constantize(name)
    constantize(name)
  rescue NameError
    nil
  end
end

require_relative 'define_simple_action/concern'
require_relative 'define_simple_action/base_services'
