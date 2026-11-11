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
          rule_configs_and_impl: T::Array[[IRuleConfig, BaseRule]],
          remaining_time: T.any(Integer, Float)
        ).returns(T::Array[RuleEngine::RuleRun])
      end
      def process_rules(event, rule_configs_and_impl, remaining_time)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        rule_configs_by_action_by_rule_impl = T.let(
          Hash.new { |a, b| a[b] = Hash.new { |c, d| c[d] = [] } },
          T::Hash[BaseRule, T::Hash[RuleEvent::EventAction, T::Array[IRuleConfig]]]
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
            T.must(T.must(rule_configs_by_action_by_rule_impl[rule_impl])[action]) << rule_config
          end
        end

        remaining_rule_impls = rule_configs_by_action_by_rule_impl.select { |impl, _| impl.is_a?(BulkRunnableRule) }
        remaining_rule_impls.each do |rule_impl, rule_configs_by_action|
          current_remaining = remaining_time - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
          rule_impl = T.cast(rule_impl, BulkRunnableRule)

          if current_remaining <= 0
            timeout_remaining_rules(remaining_rule_impls, all_rule_runs, event)
            break
          end

          trace_time("rule_evaluation", tags: ["type:#{rule_impl.rule_name}", "eval_type:bulk_per_rule"], span_attributes: { "gh.branch_protection_rule.rule_type" => rule_impl.rule_name }) do |span|
            all_rule_runs.concat(
              self.evaluate_rules(span, event, rule_configs_by_action, current_remaining, rule_impl)
            )
          end

          remaining_rule_impls = remaining_rule_impls.except(rule_impl)
        end

        all_rule_runs
      end

      sig do
        params(
          remaining_rule_impls: T::Hash[BaseRule, T::Hash[RuleEvent::EventAction, T::Array[IRuleConfig]]],
          rule_runs: T::Array[RuleRun],
          event: RuleEngine::RuleEvent,
        ).void
      end
      private def timeout_remaining_rules(remaining_rule_impls, rule_runs, event)
        remaining_rule_impls.each do |rule_impl, rule_configs_by_action|
          GitHub.dogstats.increment("repository_rule_engine.rule_evaluation_timeout", tags: ["strategy:#{self.class.name}", "rule_type:#{rule_impl.rule_name}"])
          rule_configs_by_action.each do |event_action, configs|
            configs.each do |rule_config|
              rule_runs << RuleRun.timeout_failure(rule_impl, rule_config:, event_action:)
            end
          end
        end
      end

      sig do
        params(
          tracer_span: T.untyped,
          event: RuleEngine::RuleEvent,
          rule_configs_by_action: T::Hash[RuleEngine::RuleEvent::EventAction, T::Array[IRuleConfig]],
          remaining_time: T.any(Integer, Float),
          rule_impl: RuleEngine::BulkRunnableRule,
        ).returns(T::Array[RuleRun])
      end
      private def evaluate_rules(
        tracer_span,
        event,
        rule_configs_by_action,
        remaining_time,
        rule_impl)
        rule_runs = T.let([], T::Array[RuleRun])
        begin
          timeout = remaining_time
          if timeout <= 0
            raise GitHub::Timer::Error
          end
          GitHub::Timer.timeout(timeout) do
            rule_runs = rule_impl.run_evaluation(event, rule_configs_by_action)
          end
        rescue GitHub::Timer::Error
          GitHub.logger.info("Rule engine rule timeout", {
            "gh.repo.id": event.is_a?(GitEvent) ? event.repository.id : nil,
            "gh.owner.id": event.is_a?(GitEvent) ? event.repository.owner_id : nil,
            "gh.branch_protection_rule.rule_type": rule_impl.rule_name
          })
          GitHub.dogstats.increment("repository_rule_engine.rule_evaluation_timeout", tags: ["strategy:#{self.class.name}", "rule_type:#{rule_impl.rule_name}"])
          rule_runs = rule_configs_by_action.flat_map do |event_action, configs|
            configs.map do |rule_config|
              RuleRun.timeout_failure(rule_impl, rule_config:, event_action:)
            end
          end
        end

        validate_rule_runs(rule_configs_by_action, rule_runs, event)

        rule_runs
      end
    end
  end
end
