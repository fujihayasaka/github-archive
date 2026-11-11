# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class RepositoryRulesetRuleProvider < RulesetRuleProvider
      abstract!

      sig { params(identifier: String).void }
      def initialize(identifier:)
        super(identifier:)
      end

      sig do
        override.params(
          rule_config: IRuleConfig,
          actor: Types::Actor,
          targetable: Targeting::Targetable,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, targetable, rule_run = nil)
        return false if rule_run.present? && rule_run.evaluation_metadata["bypass_prohibited"]
        return false unless rule_config.is_a?(RepositoryRuleConfiguration)
        return false unless (ruleset = rule_config.repository_ruleset)
        return false unless ruleset.definition.supports_bypass?

        GitHub::PrefillAssociations.prefill_associations(rule_config.repository_ruleset, { bypass_actors: [:actor] })

        pull_request = rule_run&.ref_update.try(:pull_request)
        ruleset_bypass_allowed?(ruleset, actor, targetable, is_pull_request: pull_request.present?)
      end

      sig do
        override.params(
          rule_config: IRuleConfig,
          actor: Types::Actor,
          targetable: Targeting::Targetable,
        ).returns(T::Boolean)
      end
      def can_skip?(rule_config, actor, targetable)
        return false unless rule_config.is_a?(RepositoryRuleConfiguration)
        return false unless (ruleset = rule_config.repository_ruleset)
        return false unless ruleset.definition.supports_bypass?

        allowed_ruleset_bypass_modes(ruleset, actor, targetable).include?(:exempt)
      end

      sig { override.params(provider_id: Integer, rule_type: String).returns(T.nilable(IRuleConfig)) }
      def fetch_rule_config(provider_id, rule_type)
        RepositoryRuleConfiguration.find_by(repository_ruleset_id: provider_id, rule_type:)
      end
    end
  end
end
