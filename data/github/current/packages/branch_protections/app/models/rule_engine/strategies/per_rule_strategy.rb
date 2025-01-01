# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Strategies
    class PerRuleStrategy < RuleEvaluationStrategy
      extend T::Helpers
      include RuleEngine::Timing

      sig { void }
      def initialize
        super(processes_type: BulkRunnableRule)
      end

      sig do
        override.params(
          event: RuleEvent,
          rule_configs_and_impl: T::Array[[RepositoryRuleConfiguration, BaseRule]],
        ).returns(T::Array[RuleEngine::RuleRun])
      end
      def process_rules(event, rule_configs_and_impl)
        rule_configs_by_action_by_rule_type = T.let(
          Hash.new { |a, b| a[b] = Hash.new { |c, d| c[d] = [] } },
          T::Hash[String, T::Hash[RuleEvent::EventAction, T::Array[RepositoryRuleConfiguration]]]
        )

        event.event_actions.each do |action|
          rule_configs_and_impl.each do |rule_config, rule_impl|
            next unless rule_config.provider_rule_matches_action?(action)

            # Uses the implementation name to handle companion rules which have different names
            T.must(T.must(rule_configs_by_action_by_rule_type[rule_impl.rule_name])[action]) << rule_config
          end
        end

        rule_configs_by_action_by_rule_type.map do |rule_type, rule_configs_by_action|
          rule_impl = GenericEvaluator.rule_impl_for_rule_type(rule_type)
          next unless rule_impl && rule_impl.is_a?(BulkRunnableRule)

          trace_time("rule_evaluation", tags: ["type:#{rule_type}", "eval_type:bulk_per_rule"], span_attributes: { "gh.branch_protection_rule.rule_evaluation" => rule_type }) do
            rule_runs = rule_impl.run_evaluation(event, rule_configs_by_action)

            validate_rule_runs(rule_configs_by_action, rule_runs, event.is_a?(RepositoryEvent) ? event.repository : nil)

            rule_runs
          end
        end.flatten.compact
      end
    end
  end
end
