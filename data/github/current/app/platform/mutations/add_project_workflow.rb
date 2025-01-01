# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectWorkflow < Platform::Mutations::Base
      visibility :internal
      description "Adds a new project workflow to the project."

      minimum_accepted_scopes ["public_repo"]

      argument :project_column_id, ID, "The Node ID of the project column for the workflow.", required: true, loads: Objects::ProjectColumn
      argument :trigger_type, Enums::ProjectWorkflowTriggerType, "The trigger type that initiates the project workflow.", required: false

      field :workflow_edge, Objects::ProjectWorkflow.edge_type, "The edge from the project's workflow connection.", null: true
      field :project_column, Objects::ProjectColumn, "The project column.", null: true

      def resolve(project_column:, **inputs)
        project = project_column.project

        context[:permission].authorize_content(:project, :update, project: project)

        viewer = context[:viewer]
        unless project.writable_by?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to add workflows to this project.")
        end

        workflow = project.project_workflows.set_workflow(trigger_type: inputs[:trigger_type], creator: viewer, column: project_column)

        if workflow.present?
          workflows_connection = Platform::ConnectionWrappers::Relation.new(project_column.project_workflows.scoped, context: context)
          {
            project_column: project_column,
            workflow_edge: GraphQL::Pagination::Connection::Edge.new(workflow, workflows_connection),
          }
        else
          # TODO: This error could be more specific about which attributes failed to save.
          raise Errors::Unprocessable.new("Could not add project workflow.")
        end
      end
    end
  end
end
