# typed: true
# frozen_string_literal: true

module Rules
  class ActionsRulesetHistory < ApplicationRecord::ActionsEnvironments
    # NOTE: Don't add any destroy callbacks to this model. Sweeper jobs won't trigger them.

    self.table_name = "actions_ruleset_histories"

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      ActionsRuleset.impl_payload
    end
    include RuleEngine::RulesetHistoryBase

    # Returns the history's state as a hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def deserialized
      @deserialized ||= state.blank? ? {} : JSON.parse(state, symbolize_names: true)
    end

    sig { returns(Rules::ActionsRuleset) }
    def ruleset_from_state
      @ruleset_from_state ||= begin
        data = deserialized.dup
        data.delete(:id)
        conditions = data.delete(:conditions)&.map { |c| c.except(:id) } || []
        rule_configs = data.delete(:rule_configurations)&.map { |rc| rc.except(:id) } || []

        ruleset = Rules::ActionsRuleset.new(data)
        ruleset.conditions = conditions.map { |c| Rules::ActionsRuleCondition.new(c) }
        ruleset.rule_configurations = rule_configs.map { |rc| Rules::ActionsRuleConfiguration.new(rc) }
        ruleset
      end
    end
  end
end
