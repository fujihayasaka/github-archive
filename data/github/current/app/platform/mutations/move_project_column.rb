# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MoveProjectColumn < Platform::Mutations::Base
      description "Moves a project column to another place."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :column_id, ID, "The id of the column to move.", required: true, loads: Objects::ProjectColumn
      argument :after_column_id, ID, "Place the new column after the column with this id. Pass null to place it at the front.", required: false, loads: Objects::ProjectColumn

      field :column_edge, Objects::ProjectColumn.edge_type, "The new edge of the moved column.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, column:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)
        column.async_project.then do |project|
          permission.typed_can_modify?("UpdateProject", project: project)
        end
      end

      def resolve(column:, **inputs)
        project = column.project

        context[:permission].authorize_content(:project, :update, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to move project cards on this project.")
        end

        after_column = if inputs[:after_column]
          if inputs[:after_column].project_id != column.project_id
            raise Errors::Validation.new("Both columns must be in the same project")
          end

          inputs[:after_column]
        else
          nil
        end

        project.move_column(column, after: after_column)

        project.notify_subscribers(
          action: "column_reorder",
          # TODO: Not sure how to properly reference the url helper outside of the controllers.
          #column_url: project_column_path(column.project, column),
          column_id: column.id,
          previous_column_id: after_column.try(:id),
        )

        connection = Platform::ConnectionWrappers::Relation.new(project.columns.scoped, context: context)

        {
          column_edge: GraphQL::Pagination::Connection::Edge.new(column, connection),
        }
      end
    end
  end
end
