# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectV2Item < Platform::Mutations::Base
      description "Deletes an item from a Project."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project from which the item should be removed.", required: true, loads: Objects::ProjectV2
      argument :item_id, ID, "The ID of the item to be removed.", required: true, loads: Objects::ProjectV2Item
      field :deleted_item_id, ID, "The ID of the deleted item.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, item:)
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
          ) &&
          item.async_readable_by_viewer?(permission.viewer)
        end
      end

      # This method has no safety checks. Need to fix this.
      def resolve(project:, item:)
        item = project.memex_project_items.find_by(id: item.id)
        if item.nil?
          raise Errors::Validation.new("The item does not exist in the project.")
        else
          deleted_item_id = item.global_relay_id
          begin
            item.destroy
          rescue GitHub::Prioritizable::Context::LockedForRebalance
            raise Errors::ServiceUnavailable.new("This project must be rebalanced.")
          end

          if item.destroyed?
            { deleted_item_id: deleted_item_id, errors: [] }
          else
            raise Errors::Unprocessable.new(item.errors.full_messages.join(", "))
          end
        end
      end
    end
  end
end
