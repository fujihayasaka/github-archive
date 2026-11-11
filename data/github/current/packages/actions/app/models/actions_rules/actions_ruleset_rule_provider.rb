# typed: strict
# frozen_string_literal: true

module ActionsRules
  class ActionsRulesetRuleProvider < RuleEngine::RuleProviders::RulesetRuleProvider
    sig { void }
    def initialize
      super(identifier: "actions_ruleset")
    end

    sig { override.params(event: RuleEngine::RuleEvent).returns(T::Array[RuleEngine::IRuleset]) }
    def load_rulesets_for_event(event)
      return [] unless event.feature_enabled?(:actions_rulesets)
      return [] unless event.is_a?(WorkflowRunEvent)

      Actions.domain.rulesets.load_rulesets(event.repository, targets: ["actions"], include_inherited: true)
    end

    sig { override.params(targetables: T::Enumerable[Targeting::Targetable]).returns(T::Array[RuleEngine::IRuleset]) }
    def load_rulesets_for_targetables(targetables)
      repositories = targetables.filter_map { |t| t.get_attribute(Targeting::Attribute::Repository) }.uniq

      rulesets = repositories.flat_map do |repository|
        Actions.domain.rulesets.load_rulesets(repository, targets: ["actions"], include_inherited: true)
      end
      rulesets.uniq
    end

    sig { override.params(provider_id: Integer, rule_type: String).returns(T.nilable(RuleEngine::IRuleConfig)) }
    def fetch_rule_config(provider_id, rule_type)
      ActionsRuleConfiguration.find_by(actions_ruleset_id: provider_id, rule_type:)
    end
  end
end
