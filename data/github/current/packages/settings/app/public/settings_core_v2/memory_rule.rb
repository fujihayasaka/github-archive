# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # In memory implementation of IRule.
  # This is used for constructing rules from the API/UI
  # or for non-persistent setting objects
  class MemoryRule
    include IRule

    sig { override.returns(String) }
    attr_reader :rule_type

    sig { override.returns(T::Hash[String, T.untyped]) }
    attr_reader :parameters

    sig { override.returns(IConditionExpression) }
    attr_reader :condition_expression

    sig { override.returns(T.nilable(ISetting)) }
    attr_reader :setting
    sig { params(setting: ISetting).void }
    attr_writer :setting

    sig { override.returns(T.nilable(Integer)) }
    attr_reader :id

    sig { override.returns(Integer) }
    attr_reader :priority

    sig { params(rule_type: String, parameters: T::Hash[T.any(String, Symbol), T.untyped], condition_expression: IConditionExpression, id: T.nilable(Integer), priority: Integer).void }
    def initialize(rule_type, parameters, condition_expression, id: nil, priority: 0)
      @rule_type = rule_type
      @parameters = T.let(parameters.stringify_keys, T::Hash[String, T.untyped])
      @condition_expression = condition_expression
      @id = id
      @priority = priority

      @setting = T.let(nil, T.nilable(ISetting))
    end

    sig { params(rule: IRule).returns(MemoryRule) }
    def self.from_interface(rule)
      MemoryRule.new(
        rule.rule_type,
        rule.parameters,
        MemoryConditionExpression.from_interface(rule.condition_expression),
        id: rule.respond_to?(:id) ? rule.id : nil,
        priority: rule.respond_to?(:priority) ? rule.priority : 0,
      )
    end

    sig { params(hash: T::Hash[String, T.untyped]).returns(MemoryRule) }
    def self.from_hash(hash)
      MemoryRule.new(
        hash.fetch("ruleType"),
        hash.fetch("parameters"),
        MemoryConditionExpression.from_hash(hash.fetch("conditionExpression")),
        id: hash["id"],
        priority: hash["priority"] || 0,
      )
    end
  end
end
