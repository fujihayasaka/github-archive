# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class RulesetRuleProvider < RuleProvider
      abstract!

      RULESET_PROVIDERS = T.let([
        "ref_ruleset",
        "push_ruleset",
        "repository_policy",
        "repository_ruleset" # legacy
      ].freeze, T::Array[String])

      include Bypasses

      def initialize(identifier:)
        super(identifier:)
      end

      sig { abstract.params(event: RepositoryEvent).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets_for_event(event); end

      sig do
        override.params(
          event: RuleEvent
        ).returns(T::Array[RepositoryRuleConfiguration])
      end
      def rules_for_event(event)
        return [] unless event.is_a?(RepositoryEvent)

        repository = event.repository

        rulesets = load_rulesets_for_event(event)

        # Preload history because this gets used on the produced RuleRuns
        GitHub::PrefillAssociations.prefill_batch_method(rulesets, :latest_history_id)

        configs_by_ref_update = Hash.new { |h, k| h[k] = [] }

        context = RuleEngine::RuleEvaluationContext.new(repository)

        rulesets.flat_map do |ruleset|
          configs = ruleset.rule_configurations.to_ary
          configs.each do |config|
            config.matching_event_actions = []
            config.provider = self
          end

          supported_rules = ruleset.available_rule_types
          event.event_actions.each do |event_action|
            composite_condition = RuleEngine::Conditions::ConditionOverride.new([event_action], event)
            next unless ruleset.should_evaluate?(composite_condition)

            configs.each do |rule|
              next unless supported_rules.include?(rule.rule_type)

              T.must(rule.matching_event_actions) << event_action
            end
          end

          configs.select { |config| config.matching_event_actions&.any? }
        end.compact
      end

      sig { override.params(rule_run: RuleRun).returns(T.nilable(String)) }
      def insights_category(rule_run)
        rule_run.source_ruleset&.name || "Deleted ruleset(s)"
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: Types::Actor,
          repository: Repository,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, repository, rule_run = nil)
        pull_request = rule_run&.ref_update.try(:pull_request)
        return false unless (ruleset = rule_config.repository_ruleset)

        GitHub::PrefillAssociations.prefill_associations(rule_config.repository_ruleset, { bypass_actors: [:actor] })

        ruleset_bypass_allowed?(ruleset, actor, repository, is_pull_request: pull_request.present?)
      end

      sig do
        overridable.params(
          repository_ruleset: RepositoryRuleset,
          actor: Types::Actor,
          repository: Repository,
          is_pull_request: T::Boolean
        ).returns(T::Boolean)
      end
      def ruleset_bypass_allowed?(repository_ruleset, actor, repository, is_pull_request:)
        actor_allowed_modes = allowed_ruleset_bypass_modes(repository_ruleset, actor, repository)

        actor_allowed_modes.include?(:any) || (is_pull_request && actor_allowed_modes.include?(:pull_request))
      end
    end
  end
end
