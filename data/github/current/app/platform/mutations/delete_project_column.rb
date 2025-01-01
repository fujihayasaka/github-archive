# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectColumn < Platform::Mutations::Base
      description "Deletes a project column."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :column_id, ID, "The id of the column to delete.", required: true, loads: Objects::ProjectColumn

      field :deleted_column_id, ID, "The deleted column ID.", null: true

      field :project, Objects::Project, "The project the deleted column was in.", null: true

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

        context[:permission].authorize_content(:project, :destroy, project: project)

        unless column.project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to delete project columns on this project.")
        end

        deletedId = column.global_relay_id
        column.destroy

        project.notify_subscribers(
          action: "column_destroyed",
        )

        {
          deleted_column_id: deletedId,
          project: project,
        }
      end
    end
  end
end
