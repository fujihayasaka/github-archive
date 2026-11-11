# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectV2LastViewed < Platform::Mutations::Base
      description "Updates the last time the viewer viewed a specific project."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      # This is application-specific for GitHub apps only.  We only want to allow tracking "last viewed"
      # as an application feature of our apps, not any other external apps.
      required_capabilities [:mobile_only_schema_mask]

      argument :project_id, ID, "The ID of the Project that was viewed.", required: true, loads: Objects::ProjectV2

      field :project_v2, Objects::ProjectV2, "The viewed Project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
        project.async_owner.then do |owner|
          current_org = owner if owner.organization?

          # We only need read access to the project to prove the current viewer can actually view
          # a project. If they have read access then this mutation will simply upsert a user-specific date/time
          # table but does not actually change anything on the project itself.
          permission.access_allowed?(
            :project_v2_read,
            current_org: current_org,
            resource: project,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, **inputs)
        project.update_last_visited_at_for_viewer(viewer: context[:viewer])

        { project_v2: project }
      end
    end
  end
end
