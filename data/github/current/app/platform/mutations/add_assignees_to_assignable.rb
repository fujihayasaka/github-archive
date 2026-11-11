# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddAssigneesToAssignable < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas
      include Platform::Helpers::Agentic

      description "Adds assignees to an assignable object."

      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to add assignees to.", required: true, loads: Interfaces::Assignable
      argument :assignee_ids, [ID], "The ids of actors (users or bots) to add as assignees.", required: true, loads: Interfaces::Actor
      # Public Copilot assignment input behind feature flag
      argument :agent_assignment, Inputs::AgentAssignmentInput, "Configuration for assigning Copilot to this issue.", required: false, visibility: :public, feature_flag: :issues_copilot_assignment_api_support

      read_arguments_from_replicas!

      error_fields
      field :assignable, Interfaces::Assignable, "The item that was assigned.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, assignable:, **inputs)
        record = assignable
        object = record.is_a?(PullRequest) ? record.issue : record
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(:edit_issue, resource: object, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(execution_errors:, assignable:, assignees:, **inputs)
        record = assignable
        issue = record.is_a?(PullRequest) ? record.issue : record

        read_from_selected_replicas([ApplicationRecord::Repositories]) do
          unless issue.assignable_by?(actor: context[:viewer])
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to manage assignees in this repository.")
          end

          issue.async_repository.then do |repository|
            if record.is_a?(Issue) && !repository.has_issues?
              raise Errors::Unprocessable::IssuesDisabled.new
            end

            if repository.locked_on_migration?
              raise Errors::Unprocessable::RepositoryMigration.new
            end

            if repository.archived?
              raise Errors::Unprocessable::RepositoryArchived.new
            end

            check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

            # Use orchestration path for Issues when feature flag is enabled
            use_orchestration = FeatureFlag.vexi.enabled?(:issues_use_orchestration_for_copilot, context[:viewer], default: false)

            if !record.is_a?(PullRequest) && use_orchestration
              # Check if Copilot should be triggered
              copilot_context = nil

              # Check if the Copilot SWE bot is assigned by looking at assignee inputs
              copilot_swe_bot_assigned = assignees.any? do |assignee|
                assignee.is_a?(Bot) && assignee.slug == Apps::Privileged::CopilotSWEAgent::SLUG
              end

              copilot_context = if copilot_swe_bot_assigned
                # Only honor public assignment input if feature flag exposes it
                agent_assignment = if FeatureFlag.vexi.enabled?(:issues_copilot_assignment_api_support, context[:viewer], default: false)
                  inputs[:agent_assignment]
                end

                target_repo = agent_assignment&.target_repository || repository
                if target_repo.present? && (!target_repo.writable_by?(context[:viewer]) || !target_repo.writable?)
                  execution_errors.add(Errors::Forbidden.new("Could not assign Copilot: target repository is not writable."))
                  # Still add non-Copilot assignees by removing Copilot from assignees
                  assignees.reject! { |a| a.is_a?(Bot) && a.slug == Apps::Privileged::CopilotSWEAgent::SLUG }
                  nil
                else
                  get_copilot_context(agent_assignment, repository)
                end
              else
                nil
              end

              # Merge new assignee IDs with existing ones
              all_assignees = (issue.assignees + assignees).uniq

              update_attributes = Issues::UpdateIssueAttributes.new(
                assignees: Issues::UpdateIssueAttribute::Set.new(all_assignees),
              )

              Issues.domain.update(issue, update_attributes, context[:viewer], copilot_context: copilot_context)

              { assignable: record, errors: [] }
            else
              # Legacy path: standard add_assignees (no Copilot support)
              # Used to respect blocks - add assignees to the issue
              GitHub.context.push(actor_id: @context[:viewer].id) do
                issue.modifying_user = @context[:viewer]

                begin
                  issue.add_assignees(assignees) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                rescue ActiveRecord::RecordInvalid => e
                  # address possible race condition where two processes update
                  # assignees at the same time
                  error_message = if e.message =~ /has already been taken/
                    e.message
                  else
                    "Something went wrong"
                  end
                  raise_unprocessable(error_message)
                end
              end

              if issue.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
                { assignable: record, errors: [] }
              else
                errors = issue.errors.full_messages.join(", ")
                raise_unprocessable(errors)
              end
            end
          end
        end
      end

      def raise_unprocessable(errors)
        raise Errors::Unprocessable.new("Could not add assignees: #{errors}")
      end

      private

      sig { params(agent_assignment: T.nilable(Inputs::AgentAssignmentInput), repository: Repository).returns(T.nilable({ request_token: String, attributes: Issues::AgentAssignmentNewAttributes })) }
      def get_copilot_context(agent_assignment, repository)
        copilot_attributes = get_copilot_attributes(agent_assignment, repository, context[:ip], viewer: context[:viewer])

        request_token_value = context[:request_token]&.to_s

        token = if request_token_value.present?
          GitHub.encrypt_and_encode_capi_token(request_token_value)
        else
          CopilotSessions::CopilotApiToken.get_encrypted(
            user: context[:viewer],
            entry_point: :add_assignees_to_assignable_mutation,
            user_session: context[:user_session]
          )
        end

        {
          request_token: token.to_s,
          attributes: copilot_attributes,
        }
      rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
        # Copilot SWE Agent integration is not available (e.g., on GHES)
        # Return nil to skip agent assignment
        nil
      end
    end
  end
end
