# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectColumn < Platform::Mutations::Base
      description "Updates an existing project column."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :project_column_id, ID, "The ProjectColumn ID to update.", required: true, loads: Objects::ProjectColumn, as: :column
      # TODO indec - when purposes are public, make name optional
      # Currently left as required so as not to change the public schema
      argument :name, String, "The name of project column.", required: true
      argument :purpose, Enums::ProjectColumnPurpose, "The semantic purpose of the column", visibility: :internal, required: false

      field :project_column, Objects::ProjectColumn, "The updated project column.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, column:, **inputs)
        column.async_project.then do |project|
          permission.typed_can_modify?("UpdateProject", project: project)
        end
      end

      def resolve(column:, **inputs)
        project = column.project

        context[:permission].authorize_content(:project, :update, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update projects on this repository.")
        end

        # TODO indec - when purposes are public, make name optional
        column.name = inputs[:name] if inputs.key?(:name)
        column.purpose = inputs[:purpose] if inputs.key?(:purpose)

        if column.save
          { project_column: column }
        else
          raise Errors::Unprocessable.new(column.errors.full_messages.join(", "))
        end
      end
    end
  end
end
