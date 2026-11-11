# typed: strict
# frozen_string_literal: true

module SettingsCore
  class SimpleRuleValidator < RuleEvaluator
    extend T::Helpers
    extend T::Generic

    EvaluationContext = type_member

    sig { returns(String) }
    attr_reader :rule_type

    sig do
      params(
        rule_type: String,
        validator: T.proc.params(
          definition: SettingDefinition[EvaluationContext, T.untyped],
          original_value: EvaluationContext,
          new_value: EvaluationContext,
          rule: IRule,
          current_result: SettingDefinition::ValidationResult
        ).returns(SettingDefinition::ValidationResult)
      ).void
    end
    def initialize(rule_type, &validator)
      @rule_type = rule_type
      @validator = validator
    end

    sig do
      override.params(
        definition: SettingDefinition[EvaluationContext, T.untyped],
        original_value: EvaluationContext,
        new_value: EvaluationContext,
        rule: IRule,
        current_result: SettingDefinition::ValidationResult
      ).returns(SettingDefinition::ValidationResult)
    end
    def validation_result(definition, original_value, new_value, rule, current_result)
      @validator.call(definition, original_value, new_value, rule, current_result)
    end
  end
end
