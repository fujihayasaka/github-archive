# typed: strict
# frozen_string_literal: true

module SettingsCore
  # Rules are run during setting evaluation
  # They can either modify the current value of the setting
  # or provide validation errors if the rule is violated
  class RuleEvaluator
    extend T::Helpers
    extend T::Generic

    EvaluationContext = type_member

    abstract!

    sig { returns(String) }
    attr_reader :rule_type

    sig { params(rule_type: String).void }
    def initialize(rule_type)
      @rule_type = rule_type
    end

    # Run before evaluating the current resource
    # current_value represents the value of the setting after evaluating parent resources
    # The implementation should return the updated value after applying the rule
    sig do
      overridable.params(
        setting_name: String,
        current_value: EvaluationContext,
        rule: IRule
      ).returns(EvaluationContext)
    end
    def perform_rule(setting_name, current_value, rule)
      current_value
    end

    # Run after evaluating the current resource
    # original_value represents the value of the setting before evaluating the current resource
    # new_value represents the value of the setting after evaluating the current resource
    # The implementation should return a ValidationResult indicating whether the change is allowed
    sig do
      overridable.params(
        setting_name: String,
        original_value: EvaluationContext,
        new_value: EvaluationContext,
        rule: IRule,
        current_result: SettingDefinition::ValidationResult
      ).returns(SettingDefinition::ValidationResult)
    end
    def validation_result(setting_name, original_value, new_value, rule, current_result)
      current_result
    end
  end
end
