# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module TargetTag

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def target_required_condition_targets
      [RuleEngine::Conditions::ConditionTarget::TargetObject::Ref]
    end

    sig { params(targetable: RuleEngine::Conditions::Targetable).returns(T::Boolean) }
    def target_supports_targetable?(targetable)
      ref_name = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::RefName)
      # fail open if we don't have a ref_name to support partial condition checking
      return true unless ref_name.is_a?(String)
      ref_name.start_with?("refs/tags/")
    end
  end
end
