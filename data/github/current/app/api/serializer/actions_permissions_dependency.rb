# typed: false
# frozen_string_literal: true

module Api::Serializer::ActionsPermissionsDependency
  def actions_repository_permissions_hash(data, options = {})
    data.slice(
      :enabled,
      :allowed_actions,
      :selected_actions_url,
      :sha_pinning_required
    ).compact
  end

  def actions_repository_selected_actions_hash(data, options = {})
    data.slice(:github_owned_allowed, :patterns_allowed, :verified_allowed)
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
      :selected_actions_url,
      :sha_pinning_required
    ).compact
  end

  def actions_enterprise_allowed_organizations_hash(data, options = {})
    {
      total_count: data[:total_count],
      organizations: data[:organizations].map { |org| organization_hash(org, options) }
    }
  end

  def actions_organization_permissions_hash(data, options = {})
    data.slice(
      :enabled_repositories,
      :selected_repositories_url,
      :allowed_actions,
      :selected_actions_url,
      :sha_pinning_required
    ).compact
  end

  def actions_enterprise_selected_actions_hash(data, options = {})
    data.slice(:github_owned_allowed, :patterns_allowed, :verified_allowed)
  end

  def actions_organization_allowed_repositories_hash(data, options = {})
    {
      total_count: data[:total_count],
      repositories: data[:repositories].map { |repo| repository_hash(repo, options) }
    }
  end

  def actions_organization_selected_actions_hash(data, options = {})
    data.slice(:github_owned_allowed, :patterns_allowed, :verified_allowed)
  end

  def actions_default_workflow_permissions_hash(data, options = {})
    {
      default_workflow_permissions: data[:default_workflow_permissions],
      can_approve_pull_request_reviews: data[:can_approve_pull_request_reviews]
    }.compact
  end

  def actions_fork_pr_contributor_approval_hash(data, options = {})
    {
      approval_policy: data[:approval_policy]
    }
  end

  def actions_fork_pr_workflows_private_repos_hash(data, options = {})
    {
      run_workflows_from_fork_pull_requests: data[:run_workflows_from_fork_pull_requests],
      send_write_tokens_to_workflows: data[:send_write_tokens_to_workflows],
      send_secrets_and_variables: data[:send_secrets_and_variables],
      require_approval_for_fork_pr_workflows: data[:require_approval_for_fork_pr_workflows]
    }.compact
  end

  def self_hosted_runners_settings_hash(data, options = {})
    {
      enabled_repositories: data[:enabled_repositories],
      selected_repositories_url: data[:selected_repositories_url]
    }.compact
  end

  def enterprise_self_hosted_runners_hash(data, options = {})
    {
      disable_self_hosted_runners_for_all_orgs: data[:disable_self_hosted_runners_for_all_orgs]
    }
  end

  def actions_artifact_log_retention_settings_hash(data, options = {})
    {
      days: data[:days],
      maximum_allowed_days: data[:maximum_allowed_days]
    }
  end
end
