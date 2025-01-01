# typed: false
# frozen_string_literal: true

module Api::Serializer::ActionsPermissionsDependency
  def actions_repository_permissions_hash(data, options = {})
    {
      enabled: data[:enabled],
      allowed_actions: data[:allowed_actions],
      selected_actions_url: data[:selected_actions_url]
    }.compact
  end

  def actions_repository_selected_actions_hash(data, options = {})
    if GitHub.enterprise?
      # Verified is unavailable for GHES
      data.slice(:github_owned_allowed, :patterns_allowed)
    else
      data.slice(:github_owned_allowed, :patterns_allowed, :verified_allowed)
    end
  end

  def actions_repository_share_policy_hash(data, options = {})
    {
      access_level: data[:access_level]
    }
  end

  def actions_enterprise_permissions_hash(data, options = {})
    data.slice(
      :enabled_organizations,
      :selected_organizations_url,
      :allowed_actions,
      :selected_actions_url
    ).compact
  end

  def actions_enterprise_allowed_organizations_hash(data, options = {})
    {
      total_count: data[:total_count],
      organizations: data[:organizations].map { |org| organization_hash(org, options) }
    }
  end

  def actions_organization_permissions_hash(data, options = {})
    {
      enabled_repositories: data[:enabled_repositories],
      selected_repositories_url: data[:selected_repositories_url],
      allowed_actions: data[:allowed_actions],
      selected_actions_url: data[:selected_actions_url]
    }.compact
  end

  def actions_enterprise_selected_actions_hash(data, options = {})
    if GitHub.enterprise?
      # Verified is unavailable for GHES
      data.slice(:github_owned_allowed, :patterns_allowed)
    else
      data.slice(:github_owned_allowed, :patterns_allowed, :verified_allowed)
    end
  end

  def actions_organization_allowed_repositories_hash(data, options = {})
    {
      total_count: data[:total_count],
      repositories: data[:repositories].map { |repo| repository_hash(repo, options) }
    }
  end

  def actions_organization_selected_actions_hash(data, options = {})
    if GitHub.enterprise?
      # Verified is unavailable for GHES
      data.slice(:github_owned_allowed, :patterns_allowed)
    else
      data.slice(:github_owned_allowed, :patterns_allowed, :verified_allowed)
    end
  end

  def actions_default_workflow_permissions_hash(data, options = {})
    {
      default_workflow_permissions: data[:default_workflow_permissions],
      can_approve_pull_request_reviews: data[:can_approve_pull_request_reviews]
    }.compact
  end
end
