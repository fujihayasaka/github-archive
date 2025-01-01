# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectV2 < Platform::Mutations::Base
      description "Delete a project."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project to delete.", required: true, loads: Objects::ProjectV2

      field :project_v2, Objects::ProjectV2, "The deleted Project.", null: true

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
        viewer = context[:viewer]

        project.soft_delete!(viewer)
        GlobalInstrumenter.instrument("memex_event",
          {
            actor: context[:viewer],
            memex_project: project,
            name: "soft_delete",
            ui: "graphql",
          }
        )

        if !project.project_migration.nil?
          project.project_migration.destroy!
        end

        { project_v2: project }
      end
    end
  end
end
