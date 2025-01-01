# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectV2 < Platform::Mutations::Base
      description "Updates an existing project."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project to update.", required: true, loads: Objects::ProjectV2
      argument :title, String, "Set the title of the project.", required: false
      argument :short_description, String, "Set the short description of the project.", required: false
      argument :readme, String, "Set the readme description of the project.", required: false
      argument :closed, Boolean, "Set the project to closed or open.", required: false
      argument :public, Boolean, "Set the project to public or private.", required: false

      field :project_v2, Objects::ProjectV2, "The updated Project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

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

      def resolve(project:, **inputs)
        async_viewer_can_change_visibility = if inputs[:public].nil?
          Promise.resolve(true)
        else
          project.async_viewer_can_change_visibility?(context[:viewer])
        end

        async_viewer_can_change_visibility.then do |viewer_can_change_visibility|
          unless viewer_can_change_visibility
            raise Errors::Forbidden.new("Viewer not authorized to change project visibility")
          end

          project.public = inputs[:public] unless inputs[:public].nil?
          project.closed_at = (inputs[:closed] ? Time.zone.now : nil) unless inputs[:closed].nil?

          project.title = inputs[:title] if inputs[:title].present?
          project.short_description = inputs[:short_description] if inputs[:short_description].present?
          project.description = inputs[:readme] if inputs[:readme].present?

          next { project_v2: project } if project.save

          raise Errors::Unprocessable.new(project.errors.full_messages.join(", "))
        end
      end
    end
  end
end
