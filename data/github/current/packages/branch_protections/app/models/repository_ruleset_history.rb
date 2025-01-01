# typed: true
# frozen_string_literal: true

class RepositoryRulesetHistory < ApplicationRecord::Repositories
  # NOTE: Don't add any destroy callbacks to this model. The RulesetSweeperJob won't trigger them.
  include GitHub::FlipperActor
  include GitHub::VexiActor # both flipperactor and vexiactor can be removed when the FF check is removed
  self.table_name = "repository_ruleset_histories"

  belongs_to :repository_ruleset, class_name: "RepositoryRuleset"

  belongs_to :updated_by, class_name: "User"

  validates :repository_ruleset, presence: true
  validates :state, presence: true
  validates :updated_by_id, presence: true

  # Returns the history's state as a hash
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def deserialized
    @deserialized ||= state.blank? ? {} : JSON.parse(state, symbolize_names: true)
  end

  sig { returns(RepositoryRuleset) }
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
