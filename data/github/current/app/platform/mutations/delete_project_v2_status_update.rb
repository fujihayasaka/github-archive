# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectV2StatusUpdate < Platform::Mutations::Base
      description "Deletes a project status update."

      minimum_accepted_scopes ["project"]

      argument :status_update_id, ID, "The ID of the status update to be removed.", required: true, loads: Objects::ProjectV2StatusUpdate

      field :deleted_status_update_id, ID, "The ID of the deleted status update.", null: true

      field :project_v2, Objects::ProjectV2, "The project the deleted status update was in.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, status_update:)
        status_update.async_memex_project.then do |project|
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
      end

      def resolve(status_update:)
        deleted_status_update_id = status_update.global_relay_id

        return {
          deleted_status_update_id: deleted_status_update_id,
          project_v2: status_update.memex_project
        } if status_update.destroy

        raise Errors::Unprocessable.new("Could not delete project status update.")
      end
    end
  end
end
