# typed: true
# frozen_string_literal: true

module ActionsRules
  class ActionsRulesetHistory < ApplicationRecord::ActionsEnvironments
    # NOTE: Don't add any destroy callbacks to this model. Sweeper jobs won't trigger them.

    self.table_name = "actions_ruleset_histories"

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      ActionsRuleset.impl_payload
    end
    include RuleEngine::RulesetHistoryBase

    sig { override.returns(ActionsRuleset) }
    def ruleset_from_state
      @ruleset_from_state ||= begin
        data = deserialized.dup
        data.delete(:id)
        conditions = data.delete(:conditions)&.map { |c| c.except(:id) } || []
        rule_configs = data.delete(:rule_configurations)&.map { |rc| rc.except(:id) } || []

        ruleset = ActionsRuleset.new(data)
        ruleset.conditions = conditions.map { |c| ActionsRuleCondition.new(c) }
        ruleset.rule_configurations = rule_configs.map { |rc| ActionsRuleConfiguration.new(rc) }
        ruleset
      end
    end

    sig { returns(T::Boolean) }
    def is_current # rubocop:disable Naming/PredicatePrefix
      T.must(actions_ruleset).histories.first == self
    end
  end
end
