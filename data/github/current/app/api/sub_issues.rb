# typed: true
# frozen_string_literal: true

class Api::SubIssues < Api::App
  include Api::Issues::Preload
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::HandleIssueNotFound
  include Api::Issues::Limits
  include Api::App::UsersDependency
  include Api::App::DatabaseConnectionHelper
  include Api::DatabaseResourceUpdateRateLimiting

  # Get the parent issue of the provided issue
  get "/repositories/:repository_id/issues/:issue_number/parent", operation_id: "issues/get-parent" do
    deliver_error!(404) unless current_repo
    issue = find_issue_by_number
    handle_issue_not_found("/parent") unless issue

    control_access :get_issue_parent,
      repo: current_repo,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    parent_promise = issue.async_filtered_parent(viewer: current_user, cap_filter: cap_filter) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    deliver_error!(404, message: "No parent issue found") unless parent_promise

    parent_issue = parent_promise.sync
    deliver_error!(404, message: "No parent issue found") unless parent_issue

    updated_issue_prefillers_enabled = FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
    options = if updated_issue_prefillers_enabled
      Api::SerializerOptions.fill(default_options)
    else
      nil
    end

    prefill_for_multiple_issues([parent_issue], options: options, updated_issue_prefillers_enabled: updated_issue_prefillers_enabled)

    deliver :issue_hash, parent_issue, repositories: true
  end

  # List issues for the current user across all organization, owned, and member repositories
  get "/repositories/:repository_id/issues/:issue_number/sub_issues", operation_id: "issues/list-sub-issues" do
    deliver_error!(404) unless current_repo
    parent_issue = find_issue_by_number
    handle_issue_not_found("/sub_issues") unless parent_issue

    control_access :list_issue_sub_issues,
      repo: current_repo,
      resource: parent_issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    sub_issues = parent_issue.async_filtered_prioritized_sub_issues(viewer: current_user, cap_filter: cap_filter).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    sub_issues = paginate_rel(sub_issues)
    updated_issue_prefillers_enabled = FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
    options = if updated_issue_prefillers_enabled
      Api::SerializerOptions.fill(default_options)
    else
      nil
    end

    prefill_for_multiple_issues(sub_issues, options: options, updated_issue_prefillers_enabled: updated_issue_prefillers_enabled)

    deliver :issue_hash, sub_issues, repositories: true
  end

  # Add a sub-issue to the provided issue
  post "/repositories/:repository_id/issues/:issue_number/sub_issues", operation_id: "issues/add-sub-issue" do
    deliver_error!(404) unless current_repo
    parent_issue = find_issue_by_number
    handle_issue_not_found("/sub_issues") unless parent_issue

    data = receive_with_openapi
    sub_issue = find_sub_issue!(data["sub_issue_id"])

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
    deliver_error!(404) unless current_repo
    parent_issue = find_issue_by_number
    handle_issue_not_found("/sub_issue") unless parent_issue

    data = receive_with_openapi
    child_issue = find_sub_issue!(data["sub_issue_id"])

    sub_issue = SubIssue.find_by(
      source_issue_id: parent_issue.id,
      source_repository_id: current_repo.id,
      target_issue_id: child_issue.id,
    )

    control_access :remove_sub_issue,
      resource: sub_issue,
      source_repository: current_repo,
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
    deliver_error!(404) unless current_repo
    parent_issue = find_issue_by_number
    handle_issue_not_found("/sub_issues") unless parent_issue

    data = receive_with_openapi

    child_issue = find_sub_issue!(data["sub_issue_id"])

    if parent_issue.id == child_issue.id
      deliver_error!(422, message: "A sub-issue cannot be prioritized against itself")
    end

    sub_issue = SubIssue.find_by(
      source_issue_id: parent_issue.id,
      source_repository_id: current_repo.id,
      target_issue_id: child_issue.id,
    )

    deliver_error!(404, message: "Sub-issue relationship does not exist") unless sub_issue

    control_access :update_sub_issue,
      resource: sub_issue,
      source_repository: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_database_resource_update_rate_limit!(resource: sub_issue, repo: current_repo, current_user: current_user)

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

    before = before_id.present? ? Issue.find(before_id) : nil # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    after = after_id.present? ? Issue.find(after_id) : nil # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    # Ensure that the user also has read access to the sub-issue
    unless access_allowed?(:show_issue, resource: after || before, repo: current_repo, allow_integrations: true, allow_user_via_granular_actor: true)
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

  private

  def find_issue_by_number
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    T.cast(issue, Issue) if issue
  end

  def find_sub_issue!(sub_issue_id)
    issue = Issue.includes(:repository).find_by(id: sub_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    record_or_404(issue, error_options: { message: "The provided sub-issue does not exist" })
  end
end
