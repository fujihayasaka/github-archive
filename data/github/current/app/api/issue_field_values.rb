# typed: true
# frozen_string_literal: true

class Api::IssueFieldValues < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::DatabaseResourceUpdateRateLimiting
  include Api::App::DatabaseConnectionHelper
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::HandleIssueNotFound
  include Api::Issues::IssueFieldValuesHelper


  # List issue field values for an issue
  get "/repositories/:repository_id/issues/:issue_number/issue-field-values", operation_id: "issues/list-issue-field-values-for-issue" do
    repo = current_repo
    deliver_error!(404) unless IssueFieldsFeature.enabled?(repo, actor: current_user)

    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/issue-field-values") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "list-issue-field-values-for-issue")

    control_access :list_issue_field_values,
      resource: issue,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_issues_enabled_or_pr! repo, issue

    field_values = Issues.domain.issue_fields.get_issue_field_values_from_issues([issue.id])[issue.id] || []

    deliver :issue_field_value_for_api_hash, field_values
  end

  # Add issue field values to an issue
  post "/repositories/:repository_id/issues/:issue_number/issue-field-values", operation_id: "issues/add-issue-field-values", read_from_replicas: true do
    if !IssueFieldsFeature.enabled?(current_repo, actor: current_user)
      deliver_error! 404
    end

    repo = current_repo
    issue  = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/issue-field-values") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "add-issue-field-values")

    # TODO: Should we define a more granular role?
    control_access :triage_issue,
      repo: repo,
      resource: issue,
      challenge: repo.public?,
      # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
      # Therefore, we could leave off the integration-related key/value pairs in this call.
      # However, that would count against our linter, so for completeness, we are adding them.
      forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr! repo, issue

    data = receive_with_schema("issue-field-value", "add-issue-field-values")

    # The schema validation will handle the format validation for us
    field_values = if data.is_a?(Hash) && data["issue_field_values"].is_a?(Array)
      data["issue_field_values"]
    else
      data
    end

    existing_issue_field_values = Issues.domain.issue_fields.get_issue_field_values_from_issues([issue.id])[issue.id]
    existing_issue_field_ids = T.must(existing_issue_field_values).map(&:issue_field).map(&:id)

    update_attributes = get_issue_field_update_attributes(existing_issue_field_ids, field_values, "add")

    issue_attributes = Issues::UpdateIssueAttributes.new(issue_fields: update_attributes)
    with_write do
      result = Issues.domain.update(issue, issue_attributes, current_user)
      if result.is_a?(GH::Result::Error)
        deliver_error! 422, message: "Failed to update issue field values: #{result.message}"
      end
    end

    deliver :issue_field_value_for_api_hash, Issues.domain.issue_fields.get_issue_field_values_from_issues([issue.id])[issue.id]
  end

  # Set issue field values in an issue
  put "/repositories/:repository_id/issues/:issue_number/issue-field-values", operation_id: "issues/set-issue-field-values", read_from_replicas: true do
    if !IssueFieldsFeature.enabled?(current_repo, actor: current_user)
      deliver_error! 404
    end
    repo = current_repo
    issue  = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/issue-field-values") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "set-issue-field-values")

    # TODO: Should we define a more granular role?
    control_access :triage_issue,
      repo: repo,
      resource: issue,
      challenge: repo.public?,
      # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
      # Therefore, we could leave off the integration-related key/value pairs in this call.
      # However, that would count against our linter, so for completeness, we are adding them.
      forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr! repo, issue

    data = receive_with_schema("issue-field-value", "set-issue-field-values")

    # The schema validation will handle the format validation for us
    field_values = if data.is_a?(Hash) && data["issue_field_values"].is_a?(Array)
      data["issue_field_values"]
    else
      data
    end

    existing_issue_field_values = Issues.domain.issue_fields.get_issue_field_values_from_issues([issue.id])[issue.id]
    existing_issue_field_ids = T.must(existing_issue_field_values).map(&:issue_field).map(&:id)

    update_attributes = get_issue_field_update_attributes(existing_issue_field_ids, field_values, "set")

    issue_attributes = Issues::UpdateIssueAttributes.new(issue_fields: update_attributes)
    with_write do
      result = Issues.domain.update(issue, issue_attributes, current_user)
      if result.is_a?(GH::Result::Error)
        deliver_error! 422, message: "Failed to update issue field values: #{result.message}"
      end
    end

    deliver :issue_field_value_for_api_hash, Issues.domain.issue_fields.get_issue_field_values_from_issues([issue.id])[issue.id]
  end

  # Delete an issue field value from an issue
  delete "/repositories/:repository_id/issues/:issue_number/issue-field-values/:issue_field_id", operation_id: "issues/delete-issue-field-value", read_from_replicas: true do
    if !IssueFieldsFeature.enabled?(current_repo, actor: current_user)
      deliver_error! 404
    end

    repo = current_repo
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    handle_issue_not_found("/issue-field-values") unless issue
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "delete-issue-field-value")

    # TODO: Should we define a more granular role?
    control_access :triage_issue,
      repo: repo,
      resource: issue,
      challenge: repo.public?,
      # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
      # Therefore, we could leave off the integration-related key/value pairs in this call.
      # However, that would count against our linter, so for completeness, we are adding them.
      forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr! repo, issue

    field_id = int_id_param!(key: :issue_field_id)

    existing_issue_field_values = Issues.domain.issue_fields.get_issue_field_values_from_issues([issue.id])[issue.id]
    existing_field_value = T.must(existing_issue_field_values).find { |v| v.issue_field.id == field_id }

    if existing_field_value.nil?
      deliver_error! 404, message: "Issue field value not found"
    end

    delete_attributes = [Issues::IssueFieldDeleteAttributes.new(field_id: field_id)]
    issue_attributes = Issues::UpdateIssueAttributes.new(issue_fields: delete_attributes)

    with_write do
      result = Issues.domain.update(issue, issue_attributes, current_user)
      if result.is_a?(GH::Result::Error)
        deliver_error! 422, message: "Failed to delete issue field value: #{result.message}"
      end
    end

    deliver_empty status: 204
  end
end
