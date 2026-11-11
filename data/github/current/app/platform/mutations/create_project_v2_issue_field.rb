# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateProjectV2IssueField < Platform::Mutations::Base
      description "Create a new project issue field."


      minimum_accepted_scopes ["project", "read:org"]

      argument :project_id, ID, "The ID of the Project to create the field in.", required: true, loads: Objects::ProjectV2
      argument :issue_field_id, ID, "The ID of the IssueField to create the field for.", required: true, loads: Unions::IssueFields

      field :project_v2_field, Unions::ProjectV2FieldConfiguration, "The new field.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
        project.async_owner.then do |owner|
          current_org = owner if owner.organization?
          permission.access_allowed?(
            :project_v2_write,
            current_org:,
            resource: project,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, issue_field:)
        viewer = context[:viewer]

        if viewer.user? && viewer.should_verify_email?
          raise Errors::Unprocessable.new("Viewer must have at least one verified email.")
        end

        unless IssueFieldsFeature.enabled?(project, actor: viewer)
          raise Errors::Forbidden.new("Project issue fields are not enabled for this project or user.")
        end

        field = project.memex_project_columns.create_with(creator: viewer).find_or_create_by(issue_field:)
        if !field.persisted?
          raise Errors::Unprocessable.new(field.errors.full_messages.join(", "))
        end

        { project_v2_field: Platform::Helpers::ProjectV2Field.coerce(field) }
      end
    end
  end
end
