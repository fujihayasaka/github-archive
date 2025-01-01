# typed: true
# frozen_string_literal: true

class Platform::Models::RulesetDeployKeyBypass
  include GitHub::Relay::GlobalIdentification

  attr_reader :repository_ruleset

  def initialize(repository_ruleset)
    @repository_ruleset = repository_ruleset
  end

  def async_repository_ruleset
    Promise.resolve(repository_ruleset)
  end

  def deploy_key
    true
  end

  # 0 == always
  def bypass_mode
    0
  end

  def actor_type
    RepositoryRulesetBypassActor::DeployKey.type
  end

  def platform_type_name
    "RepositoryRulesetBypassActor"
  end

  def repository_ruleset_id
    repository_ruleset.id
  end

  def id
    RepositoryRulesetBypassActor::DeployKey.id
  end
end
