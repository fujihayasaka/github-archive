# typed: strict
# frozen_string_literal: true

module RuleEngine
  module IRuleCondition
    extend T::Helpers

    requires_ancestor { Kernel }

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def target; end

    sig { abstract.returns(T.nilable(RuleEngine::Conditions::ConditionTarget::TargetObject)) }
    def target_object; end

    sig { abstract.returns(T::Hash[String, T.untyped]) }
    def parameters; end

    sig { abstract.returns(T.nilable(IRuleset)) }
    def ruleset; end

    sig { abstract.returns(T.nilable(RuleEngine::Conditions::ConditionTarget)) }
    def target_evaluator; end

    sig do
      params(
        condition: IRuleCondition,
        source: RuleEngine::Types::RuleSource
      ).returns(T::Boolean)
    end
    def self.supports_source?(condition, source)
      !!condition.target_evaluator&.supported_sources&.include?(source.class.name&.downcase&.to_sym)
    end

    sig do
      params(
        condition: IRuleCondition,
        target: String
      ).returns(T::Boolean)
    end
    def self.supports_ruleset_target?(condition, target)
      !!condition.target_evaluator&.supported_ruleset_targets&.include?(target.to_sym)
    end
  end
end
