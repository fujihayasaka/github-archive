# typed: strict
# frozen_string_literal: true

module RuleEngine
  # Abstract base class for rule implementations that run all configs at once per rule
  class BulkRunnableRule < BaseRule
    abstract!

    sig { params(rule_name: String, display_name: String, description: T.nilable(String), feature_flag: T.nilable(Symbol), beta: T::Boolean, beta_api: T::Boolean).void }
    def initialize(rule_name:, display_name:, description: nil, feature_flag: nil, beta: false, beta_api: false)
      super(rule_name:, display_name:, description:, feature_flag:, beta:, beta_api:)
    end

    sig { abstract.params(event: RuleEvent, rule_configs_by_action: T::Hash[RuleEvent::EventAction, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
    def run_evaluation(event, rule_configs_by_action); end
  end
end
