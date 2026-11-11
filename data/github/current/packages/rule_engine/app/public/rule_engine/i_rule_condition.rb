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
  end
end
