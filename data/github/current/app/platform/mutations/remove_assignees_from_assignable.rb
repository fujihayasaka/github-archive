# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveAssigneesFromAssignable < Platform::Mutations::Base
      description "Removes assignees from an assignable object."

      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to remove assignees from.", required: true, loads: Interfaces::Assignable
      argument :assignee_ids, [ID], "The id of users to remove as assignees.", required: true, loads: Objects::User

      field :assignable, Interfaces::Assignable, "The item that was unassigned.", null: true

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

      def resolve(assignable:, assignees:, **inputs)
        record = assignable
        issue = record.is_a?(PullRequest) ? record.issue : record

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

          issue.remove_assignees(assignees)

          if issue.save
            { assignable: record }
          else
            errors = issue.errors.full_messages.join(", ")
            raise Errors::Unprocessable.new("Could not remove assignees: #{errors}")
          end
        end
      end
    end
  end
end
