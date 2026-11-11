# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module TargetActions
    sig { returns(T::Array[String]) }
    def target_required_condition_targets
      []
    end

    sig { returns(T::Boolean) }
    def supports_bypass?
      false
    end

    sig { returns(RulesetDefinition::UIDefinition) }
    def self.ui_definition
      RulesetDefinition::UIDefinition.new(
        supportsBypass: false,
        beta: true,
        createButtonText: "New policy"
      )
    end
  end
end
