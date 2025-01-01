# typed: true
# frozen_string_literal: true

class Platform::Models::RulesetOrgAdminBypass
  include GitHub::Relay::GlobalIdentification

  attr_reader :repository_ruleset, :bypass_mode

  def initialize(repository_ruleset, bypass_mode)
    @repository_ruleset = repository_ruleset
    @bypass_mode = bypass_mode
  end

  def async_repository_ruleset
    Promise.resolve(repository_ruleset)
  end

  def organization_admin
    true
  end

  def actor_type
    "OrganizationAdmin"
  end

  def platform_type_name
    "RepositoryRulesetBypassActor"
  end

  def repository_ruleset_id
    repository_ruleset.id
  end

  def id
    RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin]
  end
end
