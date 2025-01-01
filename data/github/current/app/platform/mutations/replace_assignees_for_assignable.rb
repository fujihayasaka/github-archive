# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReplaceAssigneesForAssignable < Platform::Mutations::Base
      description "Replaces all assignees for assignable object."

      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["public_repo"]

      argument :assignable_id, ID, "The id of the assignable object to replace the assignees for.", required: true, loads: Interfaces::Assignable
      argument :assignee_ids, [ID], "The ids of the users to replace the existing assignees.", required: true, loads: Objects::User

      error_fields
      field :assignable, Interfaces::Assignable, "The item that was assigned.", null: true

      def self.async_api_can_modify?(permission, assignable:, **inputs)
        object = assignable.is_a?(PullRequest) ? assignable.issue : assignable
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(
            :replace_assignees,
            resource: object,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(assignable:, assignees:, **inputs)
        object = assignable.is_a?(PullRequest) ? assignable.issue : assignable

        unless object.assignable_by?(actor: context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to manage assignees in this repository.")
        end

        object.async_repository.then do |repository|
          if assignable.is_a?(Issue) && !repository.has_issues?
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
            object.modifying_user = @context[:viewer]
            object.assignees = assignees
          end

          if object.save
            {
              assignable: assignable,
              errors: [],
            }
          else
            {
              assignable: nil,
              errors: Platform::UserErrors.mutation_errors_for_model(object),
            }
          end
        end
      end
    end
  end
end
