# typed: true
# frozen_string_literal: true

class Api::IssueAssignees < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::DatabaseConnectionHelper
  include Api::App::Mysql1ReplicaAuth
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::IssueCopilotAssigneeHelper
  include Scientist

  sig { returns(T::Array[T.class_of(ApplicationRecord::Base)]) }
  def issue_assignees_replica_clusters
    [ApplicationRecord::Mysql1, ApplicationRecord::Repositories]
  end

  # Uses MutationIssueFragment (without repository field) to avoid primary read.
  AddIssueAssigneesQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($issueId: ID!, $assigneeIds: [ID!]!, $agentAssignment: AgentAssignmentInput, $clientMutationId: String!, $includeBody: Boolean!, $includeBodyHTML: Boolean!, $includeBodyText: Boolean!, $includePerformedViaGitHubApp: Boolean!) {
      addAssigneesToAssignable(input: {
        assignableId: $issueId,
        assigneeIds: $assigneeIds,
        agentAssignment: $agentAssignment,
        clientMutationId: $clientMutationId
      }) {
        assignable {
          ...Api::Serializer::IssuesDependency::MutationIssueFragment
          ...Api::Serializer::IssuesDependency::MutationPullRequestIssueFragment
        }
      }
    }
  GRAPHQL

  post "/repositories/:repository_id/issues/:issue_number/assignees", operation_id: "issues/add-assignees" do
    replica_clusters = issue_assignees_replica_clusters
    if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
      replica_clusters << ApplicationRecord::Collab
      replica_clusters << ApplicationRecord::Iam
    end
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
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

      assignees = lookup_assignees_by_login(data["assignees"])

      # GitHub App installation tokens cannot assign bots/agents.
      validate_rest_api_agent_assignment_allowed_by_token! if bot_assigned?(assignees)

      # Check if Copilot bot is being assigned
      copilot_assigned = copilot_assigned?(assignees)

      agent_assignment_input = nil
      if copilot_assigned
        if copilot_assignment_rest_api_support_enabled?
          agent_assignment = data["agent_assignment"] || {}
          custom_instructions = agent_assignment["custom_instructions"]
          custom_agent = agent_assignment["custom_agent"]
          model = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, current_user, default: false)
            agent_assignment["model"]
          end

          target_repo = if agent_assignment["target_repo"]
            Repository.with_name_with_owner(agent_assignment["target_repo"])
          end

          # Validate target_repo exists if explicitly provided
          if agent_assignment["target_repo"].present? && target_repo.nil?
            deliver_error! 404, message: "Target repository not found"
          end

          # Default to issue's repository if no target_repo specified
          target_repo ||= T.must(issue.repository)

          if target_repo.archived?
            deliver_error! 422, message: "Cannot assign Copilot to issues in archived repositories."
          end

          # Check write access for cross-repo assignments
          cap_unauthorized = if FeatureFlag.vexi.enabled?(:copilot_assignment_cap_target_repo_check, current_user, default: false)
            cap_filter.unauthorized_resource_ids([target_repo]).include?(target_repo.id)
          else
            false
          end
          if target_repo != issue.repository && (!target_repo.writable_by?(current_user) || !target_repo.writable? || cap_unauthorized)
            deliver_error! 404, message: "Target repository not found"
          end

          base_branch = agent_assignment["base_branch"].presence || target_repo.default_branch

          agent_assignment_input = {
            "targetRepositoryId" => target_repo.global_relay_id,
            "baseRef" => base_branch,
            "customInstructions" => custom_instructions,
            "customAgent" => custom_agent,
            "model" => model,
          }.compact
        else
          # if FF is disabled, remove copilot from the assignees array
          assignees = assignees.reject { |a| a.is_a?(Bot) && a.copilot_swe_agent? }
        end
      end

      input_variables = {
        "issueId"          => issue.global_relay_id,
        "assigneeIds"      => assignees.map(&:global_relay_id),
        "agentAssignment"  => agent_assignment_input,
        "clientMutationId" => request_id,
        "includePerformedViaGitHubApp" => false,
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

      deliver :graphql_issue_hash, results.data.add_assignees_to_assignable.assignable, status: 201,
        repo_name_with_display_owner: repo.name_with_display_owner
    end
  end

  # Uses MutationIssueFragment (without repository field) to avoid primary read.
  RemoveIssueAssigneesQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($issueId: ID!, $assigneeIds: [ID!]!, $clientMutationId: String!, $includeBody: Boolean!, $includeBodyHTML: Boolean!, $includeBodyText: Boolean!, $includePerformedViaGitHubApp: Boolean!) {
      removeAssigneesFromAssignable(input: {
        assignableId: $issueId,
        assigneeIds: $assigneeIds,
        clientMutationId: $clientMutationId
      }) {
        assignable {
          ...Api::Serializer::IssuesDependency::MutationIssueFragment
          ...Api::Serializer::IssuesDependency::MutationPullRequestIssueFragment
        }
      }
    }
  GRAPHQL

  delete "/repositories/:repository_id/issues/:issue_number/assignees", operation_id: "issues/remove-assignees" do
    replica_clusters = issue_assignees_replica_clusters
    if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
      replica_clusters << ApplicationRecord::Collab
      replica_clusters << ApplicationRecord::Iam
    end
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
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

      assignees = lookup_assignees_by_login(data["assignees"])

      # Check if Copilot bot is being removed
      copilot_being_removed = copilot_assigned?(assignees)

      # When REST API feature flag is disabled and Copilot is being removed, reject the request
      rest_api_enabled = copilot_assignment_rest_api_support_enabled?

      if !rest_api_enabled && copilot_being_removed
        deliver_copilot_assignment_not_allowed_error!(copilot_removed: true)
      end

      input_variables = {
        "issueId"          => issue.global_relay_id,
        "assigneeIds"      => assignees.map(&:global_relay_id),
        "clientMutationId" => request_id,
        "includePerformedViaGitHubApp" => false,
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
      # see: https://github.com/github/ecosystem-api/issues/1555
      _ = receive_with_schema("issue-assignee", "delete", skip_validation: true)

      deliver :graphql_issue_hash, results.data.remove_assignees_from_assignable.assignable,
        repo_name_with_display_owner: repo.name_with_display_owner
    end
  end

  # Include issue commenters when validating if a user can be assigned to an issue
  get "/repositories/:repository_id/issues/:issue_number/assignees/:username", operation_id: "issues/check-user-can-be-assigned-to-issue" do
    control_access :list_assignees,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: current_repo.id).ok
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
