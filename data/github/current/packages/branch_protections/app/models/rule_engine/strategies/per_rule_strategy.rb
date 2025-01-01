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
          remaining_time: T.any(Integer, Float)
        ).returns(T::Array[RuleEngine::RuleRun])
      end
      def process_rules(event, rule_configs_and_impl, remaining_time)
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

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rule_configs_by_action_by_rule_type.map do |rule_type, rule_configs_by_action|
          remaining_time = remaining_time - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
          rule_impl = GenericEvaluator.rule_impl_for_rule_type(rule_type)
          next unless rule_impl && rule_impl.is_a?(BulkRunnableRule)

          trace_time("rule_evaluation", tags: ["type:#{rule_type}", "eval_type:bulk_per_rule"], span_attributes: { "gh.branch_protection_rule.rule_evaluation" => rule_type }) do
            rule_runs = T.let([], T::Array[RuleRun])
            begin
              timeout_on = event.feature_enabled?(:rule_engine_rule_timeout)
              timeout = timeout_on ? remaining_time : 0
              if timeout_on && timeout <= 0
                raise GitHub::Timer::Error
              end
              GitHub::Timer.timeout(timeout) do
                rule_runs = rule_impl.run_evaluation(event, rule_configs_by_action)
              end
            rescue GitHub::Timer::Error
              GitHub.logger.info("Rule engine rule timeout", {
                "gh.repo.id": event.is_a?(GitEvent) ? event.repository.id : nil
              })
              GitHub.dogstats.increment("repository_rule_engine.rule_evaluation_timeout", tags: ["strategy:#{self.class.name}", "rule_type:#{rule_type}"])
              rule_runs = rule_configs_by_action.flat_map do |event_action, configs|
                configs.map do |rule_config|
                  RuleRun.failure(event_action:, rule_config:, message: "Unable to validate #{RuleEngine::Evaluator.rule_impl_for_rule_type(rule_config.rule_type)&.display_name}: Rule was unable to be completed in #{GenericEvaluator::RULE_TIMEOUT} seconds", evaluation_metadata: { timeout: true })
                end
              end
            end

            validate_rule_runs(rule_configs_by_action, rule_runs, event)

            rule_runs
          end
        end.flatten.compact
      end
    end
  end
end
