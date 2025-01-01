# typed: true
# frozen_string_literal: true

class Api::SubIssues < Api::App
  include Api::Issues::Preload
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::Limits
  include Api::App::UsersDependency
  include Api::App::DatabaseConnectionHelper
  include Issues::Domain::Provider

  # List issues for the current user across all organization, owned, and member repositories
  get "/repositories/:repository_id/issues/:issue_number/sub_issues", operation_id: "issues/list-sub-issues" do
    repo = find_repo!
    deliver_error!(404) unless current_repo && SubIssuesFeature.enabled?(current_repo)
    parent_issue = current_repo && issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    parent_issue = T.cast(parent_issue, Issue)

    control_access :list_issue_sub_issues,
      repo: repo,
      resource: parent_issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    sub_issues = parent_issue.async_filtered_prioritized_sub_issues(viewer: current_user, cap_filter: cap_filter).sync
    sub_issues = paginate_rel(sub_issues)
    prefill_for_multiple_issues(sub_issues)

    deliver :issue_hash, sub_issues, repositories: true
  end

  # Add a sub-issue to the provided issue
  post "/repositories/:repository_id/issues/:issue_number/sub_issues", operation_id: "issues/add-sub-issue" do
    deliver_error!(404) unless current_repo && SubIssuesFeature.enabled?(current_repo)
    parent_issue = current_repo && issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    parent_issue = T.cast(parent_issue, Issue)

    data = receive_with_openapi
    sub_issue = Issue.includes(:repository).find(data["sub_issue_id"])

    # We must create a temporary sub-issue to mimic the actual resource we will create. This allows us to perform
    # authz checks on a singular resource, as opposed to trying to check the parent and issue separately.
    temp_sub_issue = SubIssue.build(source: parent_issue, target: sub_issue, source_repository_id: parent_issue.repository_id)
    control_access :add_sub_issue,
      resource: temp_sub_issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    relationship = if data["replace_parent"]
      sub_issue.add_or_replace_parent!(parent_issue, current_user)
    else
      parent_issue.add_sub_issue!(sub_issue, current_user.id)
    end

    unless relationship.persisted?
      deliver_error!(422, message: "An error occurred while adding the sub-issue to the parent issue. #{relationship.errors.full_messages.to_sentence}")
    end

    deliver :issue_hash, parent_issue, repositories: true, calculate_sub_issue_list: true, status: 201
  end

  # Remove a sub-issue to the provided issue
  delete "/repositories/:repository_id/issues/:issue_number/sub_issue", operation_id: "issues/remove-sub-issue" do
    repo = find_repo!

    deliver_error!(404) unless current_repo && SubIssuesFeature.enabled?(current_repo)

    parent_issue = current_repo && issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    parent_issue = T.cast(parent_issue, Issue)

    data = receive_with_openapi
    child_issue = Issue.find(data["sub_issue_id"])

    sub_issue = SubIssue.find_by(
      source_issue_id: parent_issue.id,
      source_repository_id: repo.id,
      target_issue_id: child_issue.id,
    )

    control_access :remove_sub_issue,
      resource: sub_issue,
      source_repository: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      parent_issue.remove_sub_issue!(child_issue)
    rescue ActiveRecord::RecordNotDestroyed
      deliver_error!(400, message: "An error occurred while removing the sub-issue from the parent issue.")
    end

    deliver :issue_hash, parent_issue, repositories: true, status: 200
  end

  # Reprioritize a sub-issue using the before_id or after_id argument
  patch "/repositories/:repository_id/issues/:issue_number/sub_issues/priority", operation_id: "issues/reprioritize-sub-issue" do
    repo = find_repo!
    deliver_error!(404) unless current_repo && SubIssuesFeature.enabled?(current_repo)
    parent_issue = current_repo && issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    parent_issue = T.cast(parent_issue, Issue)
    data = receive_with_openapi

    begin
      child_issue = Issue.find(data["sub_issue_id"])
    rescue ActiveRecord::RecordNotFound
      deliver_error!(404, message: "The provided sub-issue does not exist")
    end

    if parent_issue.id == child_issue.id
      deliver_error!(422, message: "A sub-issue cannot be prioritized against itself")
    end

    sub_issue = SubIssue.find_by(
      source_issue_id: parent_issue.id,
      source_repository_id: repo.id,
      target_issue_id: child_issue.id,
    )

    control_access :update_sub_issue,
      resource: sub_issue,
      source_repository: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    before_id = data["before_id"]
    after_id = data["after_id"]

    unless before_id.present? || after_id.present?
      deliver_error!(422, message: "Either a before_id or after_id argument must be provided")
    end

    if before_id.present? && after_id.present?
      deliver_error!(422, message: "Only the before_id or the after_id argument may be provided, but not both")
    end

    if parent_issue.id == before_id || parent_issue.id == after_id
      deliver_error!(422, message: "The provided positional id cannot be the parent issue")
    end

    if child_issue.id == before_id || child_issue.id == after_id
      deliver_error!(422, message: "The provided positional id cannot be the child issue")
    end

    before = before_id.present? ? Issue.find(before_id) : nil
    after = after_id.present? ? Issue.find(after_id) : nil

    # Ensure that the user also has read access to the sub-issue
    unless access_allowed?(:show_issue, resource: after || before, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
      deliver_error!(403, message: "You do not have read access to the issue at the provided positional id")
    end

    prioritization_args = if before.present?
      { before: before.parent_issue_relation }
    else
      { after: T.must(after).parent_issue_relation }
    end

    unless prioritization_args.values.first&.source_issue_id == parent_issue.id
      deliver_error!(422, message: "Provided positional argument is not a sub-issue of the provided parent")
    end

    begin
      parent_issue.prioritize_dependent!(T.must(child_issue.parent_issue_relation), **prioritization_args)
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      deliver_error!(503, message: "The parent sub-issue list is currently unavailable. Please try again later.")
    end

    deliver :issue_hash, parent_issue, repositories: true, status: 200
  end
end
