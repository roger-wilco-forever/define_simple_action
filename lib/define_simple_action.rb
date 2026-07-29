# frozen_string_literal: true

require 'dry/inflector'
require 'dry/transformer'

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

  # Без ActiveSupport#deep_dup: дефолтная dry-validation-ошибка (см. BaseService#validate_params)
  # приходит с замороженными вложенными Hash — если хост (Blueprinter camelCase-трансформер
  # и т.п.) попробует мутировать её на месте, ловит FrozenError.
  def self.deep_dup(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, val), copy| copy[key] = deep_dup(val) }
    when Array
      value.map { |val| deep_dup(val) }
    else
      value
    end
  end
end

require_relative 'define_simple_action/concern'
require_relative 'define_simple_action/base_services'
