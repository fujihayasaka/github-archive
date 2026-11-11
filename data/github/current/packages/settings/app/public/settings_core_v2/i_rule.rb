# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module IRule
    extend T::Helpers
    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(ISetting)) }
    def setting; end

    sig { abstract.returns(String) }
    def rule_type; end

    sig { abstract.returns(T::Hash[String, T.untyped]) }
    def parameters; end

    sig { abstract.returns(IConditionExpression) }
    def condition_expression; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(Integer) }
    def priority; end

    sig { params(key: String).returns(T.untyped) }
    def param(key)
      parameters[key]
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def serialize
      {
        "id" => id,
        "ruleType" => rule_type,
        "priority" => priority,
        "parameters" => parameters,
        "conditionExpression" => condition_expression.serialize,
      }
    end
  end
end
