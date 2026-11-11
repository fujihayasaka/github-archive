# typed: true
# frozen_string_literal: true

class RepositoryRulesetHistory < ApplicationRecord::Repositories
  # NOTE: Don't add any destroy callbacks to this model. The RulesetSweeperJob won't trigger them.
  include GitHub::VexiActor # vexiactor can be removed when the FF check is removed
  self.table_name = "repository_ruleset_histories"

  sig { returns(RuleEngine::RulesetImplementationPayload) }
  def self.impl_payload
    RepositoryRuleset.impl_payload
  end
  include RuleEngine::RulesetHistoryBase

  sig { override.returns(RepositoryRuleset) }
  def ruleset_from_state
    @ruleset_from_state ||= (
      deserialized.delete(:id)
      conditions = deserialized.delete(:conditions)&.map { |c| c.except(:id) } || []
      bypass_actors = deserialized.delete(:bypass_actors)&.map { |ba| ba.except(:id) } || []
      rule_configs = deserialized.delete(:rule_configurations)&.map { |rc| rc.except(:id) } || []
      #legacy data fix
      deserialized[:target] = "repository" if deserialized[:target] == "member_privilege"
      ruleset = RepositoryRuleset.build(deserialized)
      ruleset.conditions = conditions.map { |c| RepositoryRuleCondition.new(c) }

      ruleset.bypass_actors = bypass_actors.map { |ba| RepositoryRulesetBypassActor.from_hash(ba) }
      ruleset.rule_configurations = rule_configs.map { |rc| RepositoryRuleConfiguration.new(rc) }
      ruleset
    )
  end

  sig { returns(T::Boolean) }
  def is_current
    T.must(repository_ruleset).histories.first == self
  end
end
