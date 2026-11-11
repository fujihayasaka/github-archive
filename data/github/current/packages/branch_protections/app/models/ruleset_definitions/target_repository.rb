# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module TargetRepository

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def target_required_condition_targets
      []
    end

    def self.ui_definition
      RulesetDefinition::UIDefinition.new(
        supportsBypass: true,
        beta: true,
        createButtonText: "New policy"
      )
    end
  end
end
