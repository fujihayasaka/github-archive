# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectWorkflow < Platform::Mutations::Base
      visibility :internal
      description "Updates an existing project workflow."

      minimum_accepted_scopes ["public_repo"]

      argument :project_workflow_id, ID, "The ProjectWorkflow ID to update.", required: true, loads: Objects::ProjectWorkflow, as: :workflow
      argument :project_column_id, ID, "The Node ID of the project column for the automation.", required: true, loads: Objects::ProjectColumn

      field :project_workflow, Objects::ProjectWorkflow, "The updated project workflow.", null: true

      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        super(permission, **inputs)
      end

      def resolve(project_column:, workflow:, **inputs)
        project = workflow.project

        context[:permission].authorize_content(:project, :update, project: project)

        viewer = context[:viewer]
        unless project.writable_by?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update workflows in this project.")
        end

        unless project_column.project == project
          raise Errors::Unprocessable.new("Could not update ProjectWorkflow; column does not belong to project.")
        end

        if workflow.set_transition_action(column: project_column, creator: viewer)
          { project_workflow: workflow }
        else
          # TODO: This error could be more specific about which attributes failed to save.
          raise Errors::Unprocessable.new("Could not update ProjectWorkflow.")
        end
      end
    end
  end
end
