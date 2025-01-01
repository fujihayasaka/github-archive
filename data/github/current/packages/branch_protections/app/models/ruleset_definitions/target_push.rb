# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module TargetPush

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def target_required_condition_targets
      []
    end

    sig do
      params(targetable: RuleEngine::Conditions::Targetable)
      .returns(RuleEngine::Conditions::Targetable)
    end
    def redirect_condition_targetable(targetable)
      return targetable unless (repository = targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Repository)).is_a?(Repository)
      if repository.fork? && (root = repository.network&.root)
        RuleEngine::Conditions::Targets::Ref.new(repository: root, ref_name: targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::RefName))
      else
        targetable
      end
    end
  end
end
