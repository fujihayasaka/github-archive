# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectColumn < Platform::Mutations::Base
      description "Adds a column to a Project."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :project_id, ID, "The Node ID of the project.", required: true, loads: Objects::Project
      argument :name, String, "The name of the column.", required: true
      argument :purpose, Enums::ProjectColumnPurpose, "The semantic purpose of the column", visibility: :internal, required: false

      field :column_edge, Objects::ProjectColumn.edge_type, "The edge from the project's column connection.", null: true

      field :project, Objects::Project, "The project", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)
        permission.typed_can_modify?("UpdateProject", project: project)
      end

      def resolve(project:, **inputs)

        context[:permission].authorize_content(:project, :update, project: project)

        if !project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("Viewer does not have permission to move project cards on this project.")
        end

        project_column = project.columns.build({
          name: inputs[:name],
          purpose: inputs[:purpose],
        })

        if project_column.save
          project.notify_subscribers(
            action: "column_create",
          )

          columns_connection = Platform::ConnectionWrappers::Relation.new(project.columns.scoped, context: context)

          {
            project: project,
            column_edge: GraphQL::Pagination::Connection::Edge.new(project_column, columns_connection),
          }
        else
          raise Errors::Unprocessable.new(project_column.errors.full_messages.join(", "))
        end
      end
    end
  end
end
