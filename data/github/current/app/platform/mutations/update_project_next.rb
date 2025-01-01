# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectNext < Platform::Mutations::Base
      description "Updates an existing project."

      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["write:org", "repo"]

      argument :project_id, ID, "The ID of the Project to update. This field is required.", required: false, loads: Objects::ProjectNext
      argument :title, String, "Set the title of the project.", required: false
      argument :description, String, "Set the readme description of the project.", required: false
      argument :short_description, String, "Set the short description of the project.", required: false
      argument :closed, Boolean, "Set the project to closed or open.", required: false
      argument :public, Boolean, "Set the project to public or private.", required: false

      field :project_next, Objects::ProjectNext, "The updated Project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        # This argument is in fact _required_ but we need to mark it as _optional_ since we are deprecating this mutation (by annotating all arguments as deprecated).
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:project, self) if inputs[:project].nil?

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_next_write,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, **inputs)
        project.public = inputs[:public] unless inputs[:public].nil?
        project.closed_at = (inputs[:closed] ? Time.zone.now : nil) unless inputs[:closed].nil?

        project.title = inputs[:title] if inputs[:title].present?
        project.description = inputs[:description] if inputs[:description].present?
        project.short_description = inputs[:short_description] if inputs[:short_description].present?

        return { project_next: project } if project.save

        raise Errors::Unprocessable.new(project.errors.full_messages.join(", "))
      end
    end
  end
end
