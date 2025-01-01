# typed: strict
# frozen_string_literal: true

module RuleEngine
  class GenericEvaluator
    extend RuleEngine::Timing

    # TODO: Move registrations here once we switch over to the generic evaluator

    # Ordered by priority
    EVALUATION_STRATEGIES = T.let([
      Strategies::CommitMetadataStrategy.new,
      Strategies::PerRuleStrategy.new,
    ].freeze, T::Array[RuleEvaluationStrategy])

    # Evaluate rules for an event
    # Returns array of RuleSuites containing the results
    sig do
      params(
        event: RuleEvent,
      ).returns(T::Array[RuleEngine::RuleSuite])
    end
    def self.evaluate_rules(event)
      validate_actor(event.actor)

      trace_time("generic_evaluation", tags: ["event_type:#{event.class.name}"], span_attributes: {
        "gh.branch_protection_rule.generic_evaluator.event_type" => event.class.name,
        "gh.branch_protection_rule.generic_evaluator.event_action_count" => event.event_actions.size
      }) do

        # Log the start of the evaluation
        GitHub.dogstats.distribution("repository_rule_engine.generic_evaluator.event_action_count", event.event_actions.size, tags: ["event_type:#{event.class.name}"])

        GitHub.logger.info(
          "Start rule evaluation",
          "code.function" => __method__,
          **log_data(event),
          "gh.branch_protections.generic_evaluator.evaluation_state" => "started",
          "gh.branch_protections.generic_evaluator.event_action_count" => event.event_actions.size,
        )

        rule_configs = event.before_evaluation(matching_rules(event))

        configs_by_strategy = T.let(
          Hash.new { |a, b| a[b] = [] },
          T::Hash[RuleEvaluationStrategy, T::Array[[RepositoryRuleConfiguration, BaseRule]]]
        )

        rule_configs.each do |config|
          rule_implementations_with_companions(config.rule_type).each do |rule_impl|
            next if rule_impl.skip_evaluation_event?(event, config)
            next unless rule_impl.is_event_feature_enabled?(event)

            strategy = evaluation_strategy_for_rule_impl(rule_impl)
            next unless strategy

            T.must(configs_by_strategy[strategy]) << [config, rule_impl]
          end
        end

        rule_runs = configs_by_strategy.flat_map do |strategy, configs|
          trace_time("generic_evaluation.strategy_evaluation", tags: ["strategy:#{strategy.class.name}"], span_attributes: {
            "gh.branch_protection_rule.generic_evaluator.strategy" => strategy.class.name
          }) do
            strategy.process_rules(event, configs)
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
        event.record_results(suites)

        suites.each do |suite|
          suite.rule_runs.map(&:rule_provider_impl).uniq.compact.each do |provider|
            provider.on_evaluation_complete(suite, event)
          end
        end

        # Log the end of the evaluation
        GitHub.logger.info(
          "End rule evaluation",
          **log_data(event),
          "code.function" => __method__,
          "gh.branch_protections.generic_evaluator.evaluation_state" => "completed",
        )

        suites
      end
    rescue StandardError => err # rubocop:disable Lint/GenericRescue allow events to handle all exceptions
      GitHub.logger.error("Rule evaluation error",
        :exception => err,
        "code.function" => __method__,
        **log_data(event),
        "gh.branch_protections.generic_evaluator.evaluation_state" => "errored",
      )

      event.handle_exception(err)
    end

    # Finds all matching rules for an event
    sig do
      params(
        event: RuleEvent
      ).returns(T::Array[RepositoryRuleConfiguration])
    end
    def self.matching_rules(event)
      provider_rules = Evaluator::RULE_PROVIDERS.filter_map do |provider|
        trace_time("generic_evaluation.matching_rules", tags: ["provider_type:#{event.class.name}", "event_type:#{event.class.name}"], span_attributes: {
          "gh.branch_protection_rule.generic_evaluator.rule_provider" => provider.class.name,
          "gh.branch_protection_rule.generic_evaluator.event_type" => event.class.name,
          "gh.branch_protection_rule.generic_evaluator.event_action_count" => event.event_actions.size
        }) do
          provider.rules_for_event(event)
        end
      end.flatten
    end

    # Public: Get the rule object for the given rule type
    #
    # rule_type - The string push policy type
    #
    # Returns a BaseRule object
    sig { params(rule_type: String).returns(T.nilable(RuleEngine::BaseRule)) }
    def self.rule_impl_for_rule_type(rule_type)
      Evaluator::REGISTERED_RULES[rule_type] || Evaluator::COMPANION_RULES[rule_type]
    end

    sig { params(rule_type: String).returns(T::Array[RuleEngine::BaseRule]) }
    def self.rule_implementations_with_companions(rule_type)
      rules = T.let([], T::Array[T.nilable(RuleEngine::BaseRule)])
      rules << Evaluator::REGISTERED_RULES[rule_type]
      rules << Evaluator::COMPANION_RULE_MAPPINGS[rule_type]
      rules.compact
    end
    private_class_method :rule_implementations_with_companions

    sig { params(rule_impl: BaseRule).returns(T.nilable(RuleEvaluationStrategy)) }
    def self.evaluation_strategy_for_rule_impl(rule_impl)
      EVALUATION_STRATEGIES.find { |strategy| rule_impl.is_a?(strategy.processes_type) }
    end
    private_class_method :evaluation_strategy_for_rule_impl

    sig { params(actor: T.untyped).void }
    def self.validate_actor(actor)
      if !actor.is_a?(User) && !actor.is_a?(PublicKey)
        raise TypeError, "expected actor to be a User or PublicKey, but was #{actor.class}"
      end
    end
    private_class_method :validate_actor

    sig { params(event: RuleEvent).returns(T::Hash[String, T.untyped]) }
    def self.log_data(event)
      data = {
        "code.namespace" => self.class.name,
        "gh.actor.id" => event.actor.try(:id),
        "gh.actor.type" => event.actor.class.name,
        "gh.branch_protections.generic_evaluator.event_type" => event.class.name,
      }

      data.merge!("gh.repo.id" => event.repository&.id)
      data.merge!("gh.org.id" => event.organization&.id)

      data
    end
    private_class_method :log_data


  end
end
