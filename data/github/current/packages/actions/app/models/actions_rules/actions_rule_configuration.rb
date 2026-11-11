# typed: true
# frozen_string_literal: true

module ActionsRules
  class ActionsRuleConfiguration < ApplicationRecord::ActionsEnvironments
    include RuleEngine::IRuleConfig

    self.table_name = "actions_rule_configurations"

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      ActionsRuleset.impl_payload
    end
    include RuleEngine::RuleConfigurationBase

    validates :rule_type, presence: true, length: { maximum: 100 }, uniqueness: { scope: [:actions_ruleset],
      message: ->(object, _data) {
        "'#{object.rule_type}' is already used for this ruleset. Only one instance of this type is allowed per ruleset."
      }
    }

    sig { override.returns(T.nilable(RuleEngine::RulesetBase)) }
    def ruleset
      actions_ruleset
    end

    sig { override.returns(T.nilable(Integer)) }
    def ruleset_id
      actions_ruleset_id
    end

    sig { override.returns(RuleEngine::DomainAccessorBase[T.untyped]) }
    def domain
      Actions.domain.rulesets
    end
  end
end
