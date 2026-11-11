# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveAssigneesFromAssignable < Platform::Mutations::Base
      docs_category :issues
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Removes assignees from an assignable object."

      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to remove assignees from.", required: true, loads: Interfaces::Assignable
      argument :assignee_ids, [ID], "The ids of actors to remove as assignees.", required: true, loads: Interfaces::Actor

      read_arguments_from_replicas!
      # Route Repositories reads during response field serialization to replicas
      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories)

      field :assignable, Interfaces::Assignable, "The item that was unassigned.", null: true

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, assignable:, **inputs)
        record = assignable
        object = record.is_a?(PullRequest) ? record.issue : record
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(:remove_assignee, resource: object, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(assignable:, assignees:, **inputs)
        record = assignable
        issue = record.is_a?(PullRequest) ? record.issue : record

        # Route Repositories and Collab reads during resolve to replicas
        clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::Collab], T::Array[T.class_of(ApplicationRecord::Base)])

        read_from_selected_replicas(clusters) do
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

            # Filter assignees to only include Users and Copilot bot (exclude other bots)
            filtered_assignees = assignees.select do |assignee|
              assignee.is_a?(User) || (assignee.is_a?(Bot) && assignee.slug == Apps::Privileged::CopilotSWEAgent::SLUG)
            end

            # Issues.domain.update will automatically handle eyes emoji removal via UpdateIssueOrchestration
            remaining_assignees = issue.assignees - filtered_assignees
            issue_attributes = Issues::UpdateIssueAttributes.new(
              assignees: Issues::UpdateIssueAttribute::Set.new(remaining_assignees)
            )
            result = Issues.domain.update(issue, issue_attributes, context[:viewer])

            if result.is_a?(GH::Result::Error)
              raise Errors::Unprocessable.new("Could not remove assignees: #{result.message}")
            end

            { assignable: record, errors: [] }
          end
        end
      end
    end
  end
end
