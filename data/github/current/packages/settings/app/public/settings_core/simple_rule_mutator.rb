# typed: strict
# frozen_string_literal: true

module SettingsCore
  class SimpleRuleMutator < RuleEvaluator
    extend T::Helpers
    extend T::Generic

    EvaluationContext = type_member

    sig { returns(String) }
    attr_reader :rule_type

    sig { params(rule_type: String, mutator: T.proc.params(setting_name: String, current_value: EvaluationContext, rule: IRule).returns(EvaluationContext)).void }
    def initialize(rule_type, &mutator)
      @rule_type = rule_type
      @mutator = mutator
    end

    sig do
      override.params(
        setting_name: String,
        current_value: EvaluationContext,
        rule: IRule
      ).returns(EvaluationContext)
    end
    def perform_rule(setting_name, current_value, rule)
      @mutator.call(setting_name, current_value, rule)
    end
  end
end
