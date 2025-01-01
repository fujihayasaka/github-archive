# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddAssigneesToAssignable < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Adds assignees to an assignable object."

      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to add assignees to.", required: true, loads: Interfaces::Assignable
      argument :assignee_ids, [ID], "The id of users to add as assignees.", required: true, loads: Objects::User

      read_arguments_from_replicas!

      field :assignable, Interfaces::Assignable, "The item that was assigned.", null: true

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

            # Used to respect blocks
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
              { assignable: record }
            else
              errors = issue.errors.full_messages.join(", ")
              raise_unprocessable(errors)
            end
          end
        end
      end

      def raise_unprocessable(errors)
        raise Errors::Unprocessable.new("Could not add assignees: #{errors}")
      end
    end
  end
end
