# typed: true
# frozen_string_literal: true

class ActionsCacheUsagePolicy
  class InvalidLimitError < StandardError; end

  def self.update_repository_cache_usage_policy(current_repository:, limit:, actor:)
    current_repository.set_actions_cache_size_limit(limit: limit, actor: actor)
  end

  def self.update_organization_cache_usage_policy(current_organization:, limit:, actor:)
    current_organization.set_actions_cache_size_limit(limit: limit, actor: actor)
  end

  def self.get_repository_cache_usage_policy(current_repository:)
    current_repository.actions_cache_size_limit
  end

  def self.update_enterprise_cache_usage_policy(current_enterprise:, limit:, upper_limit:, actor:)
    current_enterprise.set_actions_cache_size_limit_enterprise(limit: limit, upper_limit: upper_limit, actor: actor)
  end

  def self.get_enterprise_cache_usage_policy(current_enterprise:)
    {
      repo_cache_size_limit_in_gb: current_enterprise.actions_cache_size_limit,
      max_repo_cache_size_limit_in_gb: current_enterprise.max_allowed_actions_cache_size_limit
    }
  end
end
