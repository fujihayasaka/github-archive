# typed: strict
# frozen_string_literal: true

module RuleEngine
  class GenericEvaluator
    extend RuleEngine::Timing

    # Ordered by priority
    EVALUATION_STRATEGIES = T.let([
      Strategies::CommitMetadataStrategy.new,
      Strategies::PerRuleStrategy.new,
    ].freeze, T::Array[RuleEvaluationStrategy])

    RULE_TIMEOUT = 50

    sig { params(registry: RuleEngine::Registry, strategies: T::Array[RuleEvaluationStrategy]).void }
    def initialize(registry, strategies: EVALUATION_STRATEGIES)
      @registry = registry
      @strategies = strategies
    end

    # Evaluate rules for an event
    # Returns array of RuleSuites containing the results
    sig do
      params(
        event: RuleEvent,
      ).returns(T::Array[RuleEngine::RuleSuite])
    end
    def evaluate_rules(event)
      self.class.evaluate_rules(event, registry: @registry, strategies: @strategies)
    end

    # Evaluate rules for an event
    # Returns array of RuleSuites containing the results
    sig do
      params(
        event: RuleEvent,
        registry: T.nilable(RuleEngine::Registry),
        strategies: T::Array[RuleEvaluationStrategy]
      ).returns(T::Array[RuleEngine::RuleSuite])
    end
    def self.evaluate_rules(event, registry: nil, strategies: EVALUATION_STRATEGIES)
      registry ||= begin
        # temp - migrate callers to use `GenericEvaluator` instances instead of the static method
        if event.is_a?(ActionsRules::WorkflowRunEvent)
          Actions.domain.rulesets.registry
        else
          Repositories.domain.rulesets.registry
        end
      end
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      validate_actor(event.actor)

      trace_time("generic_evaluation", tags: ["event_type:#{event.class.name}"], span_attributes: {
        "gh.branch_protection_rule.generic_evaluator.event_type" => event.class.name,
        "gh.branch_protection_rule.generic_evaluator.event_action_count" => event.event_actions.size
      }.merge(event.evaluation_span_attributes)) do
        # Log the start of the evaluation
        GitHub.dogstats.distribution("repository_rule_engine.generic_evaluator.event_action_count", event.event_actions.size, tags: ["event_type:#{event.class.name}"])

        GitHub.logger.info(
          "Start rule evaluation",
          "code.function" => __method__,
          **log_data(event),
          "gh.branch_protections.generic_evaluator.evaluation_state" => "started",
          "gh.branch_protections.generic_evaluator.event_action_count" => event.event_actions.size,
        )

        rule_configs = event.before_evaluation(matching_rules(event, registry))

        configs_by_strategy = T.let(
          Hash.new { |a, b| a[b] = [] },
          T::Hash[RuleEvaluationStrategy, T::Array[[IRuleConfig, BaseRule]]]
        )

        rule_configs.each do |config|
          rule_implementations_with_companions = registry.rule_implementations_with_companions(config.rule_type)
          rule_implementations_with_companions.each do |rule_impl|
            next if rule_impl.skip_evaluation_event?(event, config)
            next unless rule_impl.is_feature_enabled?(event.feature_flag_source)

            strategy = strategies.find { |strategy| rule_impl.is_a?(strategy.processes_type) }
            next unless strategy

            T.must(configs_by_strategy[strategy]) << [config, rule_impl]
          end
        end

        effective_timeout = T.let(RULE_TIMEOUT, T.any(Integer, Float))
        if GitHub::RequestDurationManager.budgeted?
          request_budget_with_buffer = (GitHub::RequestDurationManager.remaining_time_ms / 1000.0) - 1
          effective_timeout = [effective_timeout, request_budget_with_buffer].min
        end

        rule_runs = T.let([], T::Array[RuleRun])
        remaining_configs = T.let(configs_by_strategy.to_a, T::Array[[RuleEvaluationStrategy, T::Array[[IRuleConfig, BaseRule]]]])

        begin
          raise GitHub::Timer::Error if effective_timeout <= 0

          GitHub::Timer.timeout(effective_timeout) do
            effective_timeout_with_buffer = effective_timeout - 1

            remaining_configs.each do |strategy, configs|
              trace_time("generic_evaluation.strategy_evaluation", tags: ["strategy:#{strategy.class.name}"], span_attributes: {
                "gh.branch_protection_rule.generic_evaluator.strategy" => strategy.class.name
              }) do
                remaining_time = effective_timeout_with_buffer - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
                rule_runs.concat(strategy.process_rules(event, configs, remaining_time))
              end
              remaining_configs = remaining_configs.drop(1)
            end
          end
        rescue GitHub::Timer::Error
          GitHub.logger.info("Rule engine evaluation timeout", { "gh.repo.id": event.is_a?(GitEvent) ? event.repository.id : nil })
          GitHub.dogstats.increment("repository_rule_engine.generic_evaluator_timeout")

          remaining_configs.each do |_strategy, configs|
            configs.each do |rule_config, rule_impl|
              event.event_actions.each do |action|
                next unless rule_config.provider_rule_matches_action?(action)
                rule_runs << RuleRun.timeout_failure(rule_impl, rule_config:, event_action: action)
              end
            end
          end
        end

        # Account for duplicate runs produced by companion rule evaluation
        rule_runs_by_action = rule_runs
          .sort { |rule_run| rule_run.failed? ? 0 : 1 }
          .uniq { |rule_run| [rule_run.event_action, rule_run.rule_config] }
          .group_by(&:event_action)

        suites = event.event_actions.map do |action|
          runs = rule_runs_by_action[action] || []
          RuleSuite.for_event_action(event:, action:, rule_runs: runs)
        end

        suites = event.finalize_rule_suites(suites)
        suites.each(&:check_bypasses!)
        suites.each do |suite|
          suite.rule_runs.map(&:rule_provider_impl).uniq.compact.each do |provider|
            provider.on_evaluation_complete(suite, event)
          end
        end
        event.record_results(suites)

        remaining_time_after = if GitHub::RequestDurationManager.budgeted?
          (GitHub::RequestDurationManager.remaining_time_ms / 1000.0)
        end

        GitHub.logger.info(
          "End rule evaluation",
          **log_data(event),
          "code.function" => __method__,
          "gh.branch_protections.generic_evaluator.evaluation_state" => "completed",
          "gh.branch_protections.generic_evaluator.duration" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time,
          "gh.branch_protections.generic_evaluator.remaining_time_before" => effective_timeout,
          "gh.branch_protections.generic_evaluator.remaining_time_after" => remaining_time_after,
        )

        suites
      end
    rescue StandardError => err # allow events to handle all exceptions
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time if start_time

      GitHub.logger.error("Rule evaluation error",
        :exception => err,
        "code.function" => __method__,
        **log_data(event),
        "gh.branch_protections.generic_evaluator.evaluation_state" => "errored",
        "gh.branch_protections.generic_evaluator.duration" => duration,
      )

      event.handle_exception(err)
    end

    # Finds all matching rules for an event
    sig do
      params(
        event: RuleEvent,
        registry: RuleEngine::Registry
      ).returns(T::Array[IRuleConfig])
    end
    def self.matching_rules(event, registry)
      provider_rules = registry.rule_providers.filter_map do |provider|
        trace_time("generic_evaluation.matching_rules", tags: ["provider_type:#{event.class.name}", "event_type:#{event.class.name}"], span_attributes: {
          "gh.branch_protection_rule.generic_evaluator.rule_provider" => provider.class.name,
          "gh.branch_protection_rule.generic_evaluator.event_type" => event.class.name,
          "gh.branch_protection_rule.generic_evaluator.event_action_count" => event.event_actions.size
        }) do
          provider.rules_for_event(event)
        end
      end.flatten
    end
    private_class_method :matching_rules

    sig { params(actor: T.untyped).void }
    def self.validate_actor(actor)
      if !actor.is_a?(User) && !actor.is_a?(PublicKey)
        raise TypeError, "expected actor to be a User or PublicKey, but was #{actor.class}"
      end
    end
    private_class_method :validate_actor

    sig { params(event: RuleEvent).returns(T::Hash[String, T.untyped]) }
    def self.log_data(event)
      {
        "code.namespace" => self.class.name,
      }.merge(event.evaluation_log_data)
    end
    private_class_method :log_data
  end
end
