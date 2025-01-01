# typed: true
# frozen_string_literal: true

class RepositoryRulesetHistory < ApplicationRecord::Domain::Repositories
  extend T::Sig

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
      deploy_key_bypass = false
      if bypass_actors.reject! { |ba| ba[:actor_type] == "DeployKey" }
        deploy_key_bypass = true
      end
      rule_configs = deserialized.delete(:rule_configurations)&.map { |rc| rc.except(:id) } || []
      ruleset = RepositoryRuleset.build(deserialized)
      ruleset.conditions = conditions.map { |c| RepositoryRuleCondition.new(c) }
      org_admin, bypass_actors = bypass_actors.partition { |ba| ba[:actor_type] == "OrganizationAdmin" }
      if org_admin.present?
        ruleset.bypass_mode = org_admin.first[:bypass_mode] == 0 ? :org_bypass_any : :org_bypass_prs_only
      end
      ruleset.bypass_actors = bypass_actors.map { |ba| RepositoryRulesetBypassActor.new(ba) }
      ruleset.rule_configurations = rule_configs.map { |rc| RepositoryRuleConfiguration.new(rc) }
      ruleset.deploy_key_bypass = deploy_key_bypass
      ruleset
    )
  end

  sig { returns(T::Boolean) }
  def is_current
    T.must(repository_ruleset).histories.first == self
  end
end
