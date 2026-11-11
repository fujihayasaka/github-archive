# typed: strict
# frozen_string_literal: true

module SettingsCore
  class MemoryConditionExpression
    include IConditionExpression

    sig { override.returns(T.nilable(String)) }
    attr_reader :targetable_attribute

    sig { override.returns(String) }
    attr_reader :operation

    sig { override.returns(T.nilable(String)) }
    attr_reader :value

    sig { override.returns(T::Array[IConditionExpression]) }
    attr_reader :child_condition_expressions

    sig { override.returns(T.nilable(IConditionExpression)) }
    attr_reader :root_condition_expression

    sig { override.returns(T.nilable(Integer)) }
    attr_reader :id

    sig { params(targetable_attribute: T.nilable(String), operation: String, value: T.nilable(String), child_condition_expressions: T::Array[IConditionExpression], root_condition_expression: T.nilable(IConditionExpression), id: T.nilable(Integer)).void }
    def initialize(targetable_attribute, operation, value = nil, child_condition_expressions = [], root_condition_expression: nil, id: nil)
      @targetable_attribute = targetable_attribute
      @operation = operation
      @value = value
      @child_condition_expressions = child_condition_expressions
      @root_condition_expression = root_condition_expression
      @id = id
    end

    sig { params(hash: T::Hash[String, T.untyped], root_condition_expression: T.nilable(IConditionExpression)).returns(MemoryConditionExpression) }
    def self.from_hash(hash, root_condition_expression: nil)
      expression = MemoryConditionExpression.new(
        hash.fetch("targetableAttribute"),
        hash.fetch("operation"),
        hash.fetch("value"),
        [],
        root_condition_expression: root_condition_expression,
        id: hash["id"],
      )
      expression.child_condition_expressions.concat(
        hash.fetch("childConditionExpressions", []).map { |c| MemoryConditionExpression.from_hash(c, root_condition_expression: root_condition_expression) }
      )
      expression
    end
  end
end
