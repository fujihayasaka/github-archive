# typed: strict
# frozen_string_literal: true

module SettingsCore
  class SimpleRuleMutator < RuleEvaluator
    extend T::Helpers
    extend T::Generic

    EvaluationContext = type_member

    sig { returns(String) }
    attr_reader :rule_type

    sig { params(rule_type: String, mutator: T.proc.params(definition: SettingDefinition[EvaluationContext, T.untyped], current_value: EvaluationContext, rule: IRule).returns(EvaluationContext)).void }
    def initialize(rule_type, &mutator)
      @rule_type = rule_type
      @mutator = mutator
    end

    sig do
      override.params(
        definition: SettingDefinition[EvaluationContext, T.untyped],
        current_value: EvaluationContext,
        rule: IRule
      ).returns(EvaluationContext)
    end
    def perform_rule(definition, current_value, rule)
      @mutator.call(definition, current_value, rule)
    end
  end
end
