# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnmarkProjectV2AsTemplate < Platform::Mutations::Base
      description "Unmark a project as a template."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project to unmark as a template.", required: true, loads: Objects::ProjectV2

      field :project_v2, Objects::ProjectV2, "The project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_v2_admin,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, **inputs)
        project.remove_template!


        { project_v2: project }
      end
    end
  end
end
