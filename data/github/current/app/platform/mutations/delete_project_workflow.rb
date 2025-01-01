# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectWorkflow < Platform::Mutations::Base
      visibility :internal
      description "Deletes a project workflow."

      minimum_accepted_scopes ["public_repo"]

      argument :project_workflow_id, ID, "The ProjectWorkflow ID to delete.", required: true, loads: Objects::ProjectWorkflow, as: :workflow

      field :deleted_project_workflow_id, ID, "The deleted project ID.", null: true
      field :project, Objects::Project, "The project the deleted workflow was in.", null: true

      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        super(permission, **inputs)
      end

      def resolve(workflow:, **inputs)
        project = workflow.project

        context[:permission].authorize_content(:project, :destroy, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to delete workflows in this project.")
        end

        deletedId = workflow.global_relay_id
        workflow.destroy

        {
          deleted_project_workflow_id: deletedId,
          project: project,
        }
      end
    end
  end
end
