# typed: true
# frozen_string_literal: true

class Api::IssueDependencies < Api::App
  include Api::Issues::Preload
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::HandleIssueNotFound
  include Api::Issues::Limits
  include Api::App::UsersDependency
  include Api::App::DatabaseConnectionHelper

  get "/repositories/:repository_id/issues/:issue_number/dependencies/blocked_by", operation_id: "issues/list-dependencies-blocked-by" do
    deliver_error!(404) unless current_repo && feature_enabled_for_dependencies?
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    handle_issue_not_found("/dependencies/blocked_by") unless issue
    issue = T.cast(issue, Issue)

    control_access :list_issue_dependencies,
      repo: current_repo,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    blocked_by_issues = issue.async_filtered_blocked_by(viewer: current_user, cap_filter: cap_filter).sync
    blocked_by_issues = paginate_rel(blocked_by_issues)
    updated_issue_prefillers_enabled = FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)

    options = if updated_issue_prefillers_enabled
      Api::SerializerOptions.fill(default_options)
    else
      nil
    end

    prefill_for_multiple_issues(blocked_by_issues, options: options, updated_issue_prefillers_enabled: updated_issue_prefillers_enabled)

    deliver :issue_hash, blocked_by_issues, repositories: true
  end

  get "/repositories/:repository_id/issues/:issue_number/dependencies/blocking", operation_id: "issues/list-dependencies-blocking" do
    deliver_error!(404) unless current_repo && feature_enabled_for_dependencies?
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    handle_issue_not_found("/dependencies/blocking") unless issue
    issue = T.cast(issue, Issue)

    control_access :list_issue_dependencies,
      repo: current_repo,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    blocking_issues = issue.async_filtered_blocking(viewer: current_user, cap_filter: cap_filter).sync
    blocking_issues = paginate_rel(blocking_issues)
    updated_issue_prefillers_enabled = FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)

    options = if updated_issue_prefillers_enabled
      Api::SerializerOptions.fill(default_options)
    else
      nil
    end

    prefill_for_multiple_issues(blocking_issues, options: options, updated_issue_prefillers_enabled: updated_issue_prefillers_enabled)

    deliver :issue_hash, blocking_issues, repositories: true
  end

  post "/repositories/:repository_id/issues/:issue_number/dependencies/blocked_by", operation_id: "issues/add-blocked-by-dependency", read_from_replicas: true do
    deliver_error!(404) unless current_repo && feature_enabled_for_dependencies?
    blocked_issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    handle_issue_not_found("/dependencies/blocked_by") unless blocked_issue
    blocked_issue = T.cast(blocked_issue, Issue)

    data = receive_with_openapi
    blocking_issue = Issue.includes(:repository).find_by(id: data["issue_id"]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    deliver_error!(404, message: "The provided blocking issue does not exist") unless blocking_issue

    temp_issue_dependency = IssueDependency.build(
      source_issue: blocked_issue,
      target_issue: blocking_issue,
      source_repository: blocked_issue.repository,
      target_repository: blocking_issue.repository,
      dependency_type: :blocked_by
    )

    control_access :add_issue_dependency,
      resource: temp_issue_dependency,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      begin
        blocked_issue.add_blocked_by!(blocking_issue, current_user)
        deliver :issue_hash, blocked_issue, repositories: true, calculate_issue_dependencies_summary: true, status: 201
      rescue ActiveRecord::RecordInvalid => e
        deliver_error!(422, message: "An error occurred while adding the blocking issue to the issue. #{e.message}")
      end
    end
  end

  delete "/repositories/:repository_id/issues/:issue_number/dependencies/blocked_by/:issue_id", operation_id: "issues/remove-dependency-blocked-by", read_from_replicas: true do
    deliver_error!(404) unless current_repo && feature_enabled_for_dependencies?
    blocked_issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    handle_issue_not_found("/dependencies/blocked_by") unless blocked_issue
    blocked_issue = T.cast(blocked_issue, Issue)

    blocking_issue = Issue.includes(:repository).find_by(id: int_id_param!(key: :issue_id)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    deliver_error!(404, message: "The provided blocking issue does not exist") unless blocking_issue

    temp_issue_dependency = IssueDependency.build(
      source_issue: blocked_issue,
      target_issue: blocking_issue,
      source_repository: blocked_issue.repository,
      target_repository: blocking_issue.repository,
      dependency_type: :blocked_by
    )

    control_access :remove_issue_dependency,
      source_repository: current_repo,
      resource: temp_issue_dependency,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      begin
        blocked_issue.remove_blocked_by!(blocking_issue)
      rescue ActiveRecord::RecordNotDestroyed
        deliver_error!(400, message: "An error occurred while removing the blocking issue dependency.")
      end
    end

    deliver :issue_hash, blocked_issue, calculate_issue_dependencies_summary: true, repositories: true, status: 200
  end

  private

  def feature_enabled_for_dependencies?
    return false unless current_repo

    IssueDependenciesFeature.enabled?(current_repo, actor: current_user)
  end
end
