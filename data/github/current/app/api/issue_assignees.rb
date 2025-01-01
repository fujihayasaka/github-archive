# typed: true
# frozen_string_literal: true

class Api::IssueAssignees < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Scientist
  include Issues::Domain::Provider

  AddIssueAssigneesQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($issueId: ID!, $assigneeIds: [ID!]!, $clientMutationId: String!, $includeBody: Boolean!, $includeBodyHTML: Boolean!, $includeBodyText: Boolean!) {
      addAssigneesToAssignable(input: {
        assignableId: $issueId,
        assigneeIds: $assigneeIds,
        clientMutationId: $clientMutationId
      }) {
        assignable {
          ...Api::Serializer::IssuesDependency::IssueFragment
          ...Api::Serializer::IssuesDependency::PullRequestIssueFragment
        }
      }
    }
  GRAPHQL

  post "/repositories/:repository_id/issues/:issue_number/assignees", operation_id: "issues/add-assignees" do
    repo = current_repo

    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "add-assignees")

    control_access :add_assignee,
      resource: issue,
      repo: repo,
      challenge: repo.public?,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Introducing strict validation of the issue-assignee.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("issue-assignee", "create", skip_validation: true)
    # scrub invalid input, like JSON objects: {}
    string_logins = Array(data["assignees"]).select { |assignee| assignee.is_a?(String) }
    assignees = User.where(login: string_logins)

    input_variables = {
      "issueId"          => issue.global_relay_id,
      "assigneeIds"      => assignees.map(&:global_relay_id),
      "clientMutationId" => request_id,
    }
    input_variables.update(graphql_mime_body_variables(default_options))

    results = platform_execute(AddIssueAssigneesQuery, variables: input_variables)

    if results.errors.all.any?
      errors = results.errors.all.details["data"]
      error_types = errors.map { |err| err["type"] }
      if !(error_types & %w(NOT_FOUND UNAUTHENTICATED)).empty?
        deliver_error! 404, message: "Not Found"
      elsif error_types.any? { |err| err == "FORBIDDEN" }
        deliver_error! 403, message: "Forbidden"
      elsif error_types.any? { |err| err == "REPOSITORY_MIGRATION" }
        deliver_error! 403, message: "Repository has been locked for migration."
      elsif error_types.any? { |err| err == "REPOSITORY_ARCHIVED" }
        deliver_error! 403, message: "Repository was archived so is read-only."
      elsif error_types.any? { |err| err == "ISSUES_DISABLED" }
        deliver_error! 410, message: "Issues are disabled for this repo", documentation_url: "/v3/issues/"
      else
        deliver_error! 422, errors: results.errors.all.values.flatten
      end
    end

    deliver :graphql_issue_hash, results.data.add_assignees_to_assignable.assignable, status: 201
  end

  RemoveIssueAssigneesQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($issueId: ID!, $assigneeIds: [ID!]!, $clientMutationId: String!, $includeBody: Boolean!, $includeBodyHTML: Boolean!, $includeBodyText: Boolean!) {
      removeAssigneesFromAssignable(input: {
        assignableId: $issueId,
        assigneeIds: $assigneeIds,
        clientMutationId: $clientMutationId
      }) {
        assignable {
          ...Api::Serializer::IssuesDependency::IssueFragment
          ...Api::Serializer::IssuesDependency::PullRequestIssueFragment
        }
      }
    }
  GRAPHQL

  delete "/repositories/:repository_id/issues/:issue_number/assignees", operation_id: "issues/remove-assignees" do
    repo  = current_repo

    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "remove-assignees")

    control_access :remove_assignee,
      resource: issue,
      repo: repo,
      challenge: repo.public?,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = attr(receive(Hash), :assignees)

    assignees = User.where(login: data["assignees"])

    input_variables = {
      "issueId"          => issue.global_relay_id,
      "assigneeIds"      => assignees.map(&:global_relay_id),
      "clientMutationId" => request_id,
    }
    input_variables.update(graphql_mime_body_variables(default_options))

    results = platform_execute(RemoveIssueAssigneesQuery, variables: input_variables)

    if results.errors.all.any?
      errors = results.errors.all.details["data"]
      error_types = errors.map { |err| err["type"] }
      if !(error_types & %w(NOT_FOUND UNAUTHENTICATED)).empty?
        deliver_error! 404, message: "Not Found"
      elsif error_types.any? { |err| err == "FORBIDDEN" }
        deliver_error! 403, message: "Forbidden"
      elsif error_types.any? { |err| err == "REPOSITORY_MIGRATION" }
        deliver_error! 403, message: "Repository has been locked for migration."
      elsif error_types.any? { |err| err == "REPOSITORY_ARCHIVED" }
        deliver_error! 403, message: "Repository was archived so is read-only."
      elsif error_types.any? { |err| err == "ISSUES_DISABLED" }
        deliver_error! 410, message: "Issues are disabled for this repo", documentation_url: "/v3/issues/"
      else
        deliver_error! 422, errors: results.errors.values.flatten
      end
    end

    # Introducing strict validation of the issue-assignee.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # TODO: replace `receive` with `receive_with_schema`
    # see: https://github.com/github/ecosystem-api/issues/1555
    _ = receive_with_schema("issue-assignee", "delete", skip_validation: true)

    deliver :graphql_issue_hash, results.data.remove_assignees_from_assignable.assignable
  end

  # Include issue commenters when validating if a user can be assigned to an issue
  get "/repositories/:repository_id/issues/:issue_number/assignees/:username", operation_id: "issues/check-user-can-be-assigned-to-issue" do
    control_access :list_assignees,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id)
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "check-user-can-be-assigned-to-issue")

    available_assignees = T.must(issue).visible_available_assignees_for(current_user).filter_spam_for(current_user)

    if available_assignees.pluck(:display_login).include?(params[:username])
      deliver_empty(status: 204)
    else
      deliver_error 404, message: "User cannot be assigned to this issue."
    end
  end
end
