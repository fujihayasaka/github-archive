# typed: strict
# frozen_string_literal: true

module SettingsCore
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

    sig { params(rule_type: String, parameters: T::Hash[T.any(String, Symbol), T.untyped], condition_expression: IConditionExpression, id: T.nilable(Integer)).void }
    def initialize(rule_type, parameters, condition_expression, id: nil)
      @rule_type = rule_type
      @parameters = T.let(parameters.stringify_keys, T::Hash[String, T.untyped])
      @condition_expression = condition_expression
      @id = id

      @setting = T.let(nil, T.nilable(ISetting))
    end

    sig { params(hash: T::Hash[String, T.untyped]).returns(MemoryRule) }
    def self.from_hash(hash)
      MemoryRule.new(
        hash.fetch("ruleType"),
        hash.fetch("parameters"),
        MemoryConditionExpression.from_hash(hash.fetch("conditionExpression")),
        id: hash["id"],
      )
    end
  end
end
