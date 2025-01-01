# typed: strict
# frozen_string_literal: true

module RuleEngine
  class RuleEvaluationStrategy
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { returns(T::Class[BaseRule]) }
    attr_reader :processes_type

    sig { params(processes_type: T::Class[BaseRule]).void }
    def initialize(processes_type:)
      @processes_type = processes_type
    end

    sig do
      abstract.params(
        event: RuleEvent,
        rule_configs_and_impl: T::Array[[RepositoryRuleConfiguration, BaseRule]],
      ).returns(T::Array[RuleEngine::RuleRun])
    end
    def process_rules(event, rule_configs_and_impl); end

    protected

    sig { params(rules_by_action: T::Hash[RuleEvent::EventAction, T::Array[RepositoryRuleConfiguration]], rule_runs: T::Array[RuleRun], repository: T.nilable(Repository)).void }
    def validate_rule_runs(rules_by_action, rule_runs, repository)
      return unless repository&.feature_enabled?(:rules_engine_result_validation) ||
        repository&.owner&.feature_enabled?(:rules_engine_result_validation)

      duplicate_rule_run_types = T.let([], T::Array[String])
      missing_rule_run_types = T.let([], T::Array[String])

      grouped_rule_runs = rule_runs.group_by { |run| [run.event_action, run.rule_config] }

      rules_by_action.each do |action, configs|
        configs.each do |config|
          runs = grouped_rule_runs[[action, config]] || []

          if runs.size > 1
            duplicate_rule_run_types.push(config.rule_type)
          end

          if runs.empty?
            missing_rule_run_types.push(config.rule_type)
          end
        end
      end

      if duplicate_rule_run_types.any?
        Failbot.report(StandardError.new("Rule runs must only return a single result per action and rule configuration"), {
          "gh.branch_protection_rule.rule_types": duplicate_rule_run_types
        })
      end

      if missing_rule_run_types.any?
        Failbot.report(StandardError.new("Rule runs must return a result per action and rule configuration"), {
          "gh.branch_protection_rule.rule_types": missing_rule_run_types
        })
      end
    end
  end
end
