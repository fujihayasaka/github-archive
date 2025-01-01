# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectV2Workflow < Platform::Mutations::Base
      description "Deletes a project workflow."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :workflow_id, ID, "The ID of the workflow to be removed.", required: true, loads: Objects::ProjectV2Workflow

      field :deleted_workflow_id, ID, "The ID of the deleted workflow.", null: true

      field :project_v2, Objects::ProjectV2, "The project the deleted workflow was in.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, workflow:)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        workflow.async_memex_project.then do |project|
          project.async_owner.then do |owner|
            current_org = owner if owner.organization?

            permission.access_allowed?(
              :project_v2_write,
              current_org: current_org,
              resource: project,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      def resolve(workflow:)
        deleted_workflow_id = workflow.global_relay_id

        workflow.async_memex_project.then do |project|
          unless project.viewer_can_write?(context[:viewer])
            raise Errors::Validation.new(
              "You do not have permission to delete this workflow."
            )
          end
        end

        return {
          deleted_workflow_id: deleted_workflow_id,
          project_v2: workflow.memex_project
        } if workflow.destroy

        raise Errors::Unprocessable.new("Could not delete workflow.")
      end
    end
  end
end
