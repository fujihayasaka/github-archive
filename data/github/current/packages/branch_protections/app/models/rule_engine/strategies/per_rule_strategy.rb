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

        all_rule_runs = T.let([], T::Array[RuleRun])

        event.event_actions.each do |action|
          rule_configs_and_impl.each do |rule_config, rule_impl|
            next unless rule_config.provider_rule_matches_action?(action)
            if rule_config.can_skip?(event.actor, action)
              all_rule_runs << RuleRun.skipped(event_action: action, rule_config:)
              next
            end

            # Uses the implementation name to handle companion rules which have different names
            T.must(T.must(rule_configs_by_action_by_rule_type[rule_impl.rule_name])[action]) << rule_config
          end
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timeout_seconds = T.let(GenericEvaluator::RULE_TIMEOUT, Integer)
        runs = rule_configs_by_action_by_rule_type.map do |rule_type, rule_configs_by_action|
          remaining_time = remaining_time - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
          rule_impl = GenericEvaluator.rule_impl_for_rule_type(rule_type)
          next unless rule_impl && rule_impl.is_a?(BulkRunnableRule)

          trace_time("rule_evaluation", tags: ["type:#{rule_type}", "eval_type:bulk_per_rule"], span_attributes: { "gh.branch_protection_rule.rule_evaluation" => rule_type }) do |span|
            if event.feature_enabled?(:dynamic_rule_engine_rule_timeout) && event.feature_enabled?(:rule_engine_rule_timeout)
              begin
                  GitHub::RequestDurationManager.raise_if_time_budget_is_over(time_buffer_ms: 2000) do |remaining_time_budget_ms|
                    if !remaining_time_budget_ms.nil? && (remaining_time_budget_ms / 1000) < remaining_time
                      timeout_seconds = GitHub.default_request_timeout
                      remaining_time = (remaining_time_budget_ms / 1000)
                    end
                    self.evaluate_rules(
                      span,
                      event,
                      rule_type,
                      rule_configs_by_action,
                      remaining_time,
                      rule_impl,
                      timeout_seconds,
                    )
                  end
                rescue GitHub::RequestDurationManager::TimeBudgetIsOverError => e
                  GitHub.logger.info("Rule engine rule timeout", { "gh.repo.id": event.is_a?(GitEvent) ? event.repository.id : nil })
                  GitHub.dogstats.increment("repository_rule_engine.rule_evaluation_timeout", tags: ["strategy:#{self.class.name}", "rule_type:#{rule_type}"])
                  rule_runs = rule_configs_by_action.flat_map do |event_action, configs|
                    configs.map do |rule_config|
                      RuleRun.failure(event_action:, rule_config:, message: "Unable to validate #{RuleEngine::Evaluator.rule_impl_for_rule_type(rule_config.rule_type)&.display_name}: Rule was unable to be completed in #{GitHub.default_request_timeout} seconds", evaluation_metadata: { timeout: true })
                    end
                  end
                end
            else
              self.evaluate_rules(
                span,
                event,
                rule_type,
                rule_configs_by_action,
                remaining_time,
                rule_impl,
                timeout_seconds
              )
            end
          end
        end.flatten.compact

        all_rule_runs.concat(runs)
      end

      sig do
        params(
          tracer_span: T.untyped,
          event: RuleEngine::RuleEvent,
          rule_type: String,
          rule_configs_by_action: T::Hash[T.any(Git::Ref::Update, RuleEngine::EventActionRepositoryOperation), T::Array[RepositoryRuleConfiguration]],
          remaining_time: T.any(Integer, Float),
          rule_impl: RuleEngine::BulkRunnableRule,
          timeout_seconds: Integer
        ).returns(T::Array[RuleRun])
      end
      private def evaluate_rules(
        tracer_span,
        event,
        rule_type,
        rule_configs_by_action,
        remaining_time,
        rule_impl,
        timeout_seconds)
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
              RuleRun.failure(event_action:, rule_config:, message: "Unable to validate #{RuleEngine::Evaluator.rule_impl_for_rule_type(rule_config.rule_type)&.display_name}: Rule was unable to be completed in #{timeout_seconds} seconds", evaluation_metadata: { timeout: true })
            end
          end
        end

        validate_rule_runs(rule_configs_by_action, rule_runs, event)

        rule_runs
      end
    end
  end
end
