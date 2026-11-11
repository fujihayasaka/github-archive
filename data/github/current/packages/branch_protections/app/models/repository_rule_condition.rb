# typed: true
# frozen_string_literal: true

class RepositoryRuleCondition < ApplicationRecord::Repositories
  include RuleEngine::Timing
  include RuleEngine::IRuleCondition

  sig { returns(RuleEngine::RulesetImplementationPayload) }
  def self.impl_payload
    RepositoryRuleset.impl_payload
  end
  include RuleEngine::RuleConditionBase

  validates :target, uniqueness: { scope: [:repository_ruleset],
    message: ->(object, _data) {
      "'#{object.target}' is already used for this ruleset. Only one instance of this target is allowed per ruleset."
    }
  }

  enum :target, { ref_name: 0, repository_name: 1, repository_id: 2, repository_property: 3, organization_name: 4, organization_id: 5, organization_property: 6 }

  after_initialize :init

  def init
    self.condition_type = "fnmatch" # deprecated. We should delete the column
  end

  sig { override.returns(T.nilable(RuleEngine::RulesetBase)) }
  def ruleset
    repository_ruleset
  end
end
