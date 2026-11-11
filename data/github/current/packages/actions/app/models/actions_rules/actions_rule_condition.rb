# typed: true
# frozen_string_literal: true

module ActionsRules
  class ActionsRuleCondition < ApplicationRecord::ActionsEnvironments
    include RuleEngine::Timing
    include RuleEngine::IRuleCondition

    self.table_name = "actions_rule_conditions"

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      ActionsRuleset.impl_payload
    end
    include RuleEngine::RuleConditionBase

    validates :target, uniqueness: { scope: [:actions_ruleset],
      message: ->(object, _data) {
        "'#{object.target}' is already used for this ruleset. Only one instance of this target is allowed per ruleset."
      }
    }

    enum :target, { repository_name: 1, repository_id: 2, repository_property: 3, organization_name: 4, organization_id: 5, organization_property: 6 }

    sig { override.returns(T.nilable(RuleEngine::RulesetBase)) }
    def ruleset
      actions_ruleset
    end
  end
end
