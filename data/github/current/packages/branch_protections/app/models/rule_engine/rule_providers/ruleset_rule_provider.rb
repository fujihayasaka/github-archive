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

      # TODO: This should call `rules_for_targetables` by default and allow
      # subclasses to override it if they want to use event-specific data like the User
      sig { abstract.params(event: RuleEvent).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets_for_event(event); end

      sig { abstract.params(targetables: T::Enumerable[Conditions::Targetable]).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets_for_targetables(targetables); end

      # TODO: delete
      sig do
        override.params(
          event: RuleEvent
        ).returns(T::Array[RepositoryRuleConfiguration])
      end
      def rules_for_event(event)
        rulesets = load_rulesets_for_event(event)

        GitHub::PrefillAssociations.prefill_associations(rulesets, { bypass_actors: [:actor] })

        # Preload history because this gets used on the produced RuleRuns
        GitHub::PrefillAssociations.prefill_batch_method(rulesets, :latest_history_id)

        rulesets.flat_map do |ruleset|
          configs = ruleset.rule_configurations.to_ary
          supported_rules = ruleset.available_rule_types
          matching_event_actions = ruleset.bulk_filter_targetable(event.event_actions)
          next [] if matching_event_actions.empty?

          configs.filter_map do |config|
            next unless supported_rules.include?(config.rule_type)
            config.matching_event_actions = matching_event_actions
            config.provider = self
            config
          end
        end
      end

      sig { override.params(targetables: T::Enumerable[Conditions::Targetable]).returns(T::Hash[Conditions::Targetable, T::Array[RepositoryRuleConfiguration]]) }
      def rules_for_targetables(targetables)
        rules_by_targetable = Hash.new { |h, k| h[k] = [] }

        rulesets = load_rulesets_for_targetables(targetables)

        rulesets.flat_map do |ruleset|
          configs = ruleset.rule_configurations.to_ary
          supported_rules = ruleset.available_rule_types
          matching_targetables = ruleset.bulk_filter_targetable(targetables)
          next [] if matching_targetables.empty?

          matching_targetables.each do |targetable|
            rules_by_targetable[targetable].concat(configs.filter_map do |config|
              config if supported_rules.include?(config.rule_type)
            end)
          end
        end

        rules_by_targetable
      end

      sig { override.params(rule_run: RuleRun).returns(T.nilable(String)) }
      def insights_category(rule_run)
        rule_run.source_ruleset&.name || "Deleted ruleset(s)"
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: Types::Actor,
          targetable: Conditions::Targetable,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, targetable, rule_run = nil)
        return false if rule_run.present? && rule_run.evaluation_metadata["bypass_prohibited"]

        pull_request = rule_run&.ref_update.try(:pull_request)
        return false unless (ruleset = rule_config.repository_ruleset)

        GitHub::PrefillAssociations.prefill_associations(rule_config.repository_ruleset, { bypass_actors: [:actor] })

        ruleset_bypass_allowed?(ruleset, actor, targetable, is_pull_request: pull_request.present?)
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: Types::Actor,
          targetable: Conditions::Targetable,
        ).returns(T::Boolean)
      end
      def can_skip?(rule_config, actor, targetable)
        return false unless (ruleset = rule_config.repository_ruleset)

        allowed_ruleset_bypass_modes(ruleset, actor, targetable).include?(:exempt)
      end

      sig do
        overridable.params(
          repository_ruleset: RepositoryRuleset,
          actor: Types::Actor,
          targetable: Conditions::Targetable,
          is_pull_request: T::Boolean
        ).returns(T::Boolean)
      end
      def ruleset_bypass_allowed?(repository_ruleset, actor, targetable, is_pull_request:)
        actor_allowed_modes = allowed_ruleset_bypass_modes(repository_ruleset, actor, targetable)

        actor_allowed_modes.include?(:any) || (is_pull_request && actor_allowed_modes.include?(:pull_request))
      end
    end
  end
end
