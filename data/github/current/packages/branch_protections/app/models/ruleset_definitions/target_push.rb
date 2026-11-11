# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module TargetPush

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def target_required_condition_targets
      []
    end

    sig do
      params(targetable: Targeting::Targetable)
      .returns(Targeting::Targetable)
    end
    def redirect_condition_targetable(targetable)
      return targetable unless (repository = targetable.get_attribute(Targeting::Attribute::Repository)).is_a?(Repository)

      if repository.fork? && (root = repository.network&.root)
        ref_name = targetable.get_attribute(Targeting::Attribute::RefName)
        if ref_name
          RuleEngine::Conditions::Targets::Ref.new(repository: root, ref_name: ref_name)
        else
          Targeting::Targets::Repository.new(repository: root)
        end
      else
        targetable
      end
    end
  end
end
