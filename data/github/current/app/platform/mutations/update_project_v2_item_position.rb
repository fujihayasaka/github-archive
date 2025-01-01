# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectV2ItemPosition < Platform::Mutations::Base
      description "This mutation updates the position of the item in the project, where the position represents the priority of an item."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project.", required: true, loads: Objects::ProjectV2
      argument :item_id, ID, "The ID of the item to be moved.", required: true, loads: Objects::ProjectV2Item
      argument :after_id, ID, "The ID of the item to position this item after. If omitted or set to null the item will be moved to top.", required: false, loads: Objects::ProjectV2Item

      field :items, Connections.define(Objects::ProjectV2Item), "The items in the new order", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_v2_write,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            current_org: current_org,
            current_repo: nil,
            resource: inputs[:project]
          ) &&
          inputs[:item].async_readable_by_viewer?(permission.viewer)
        end
      end

      def resolve(project:, item:, after: nil)
        validate_input(project, item, after)
        begin
          options = after.nil? ? { position: :top } : { after: after }
          project.save_with_priority!(item, **options)
        rescue GitHub::Prioritizable::Context::LockedForRebalance, GitHub::Prioritizable::RebalanceRequiredError
          raise Errors::ServiceUnavailable.new("This project is undergoing maintenance. Please try again later.")
        rescue ActiveRecord::RecordInvalid => invalid
          raise Errors::Unprocessable.new(invalid.record.errors.full_messages.join(", "))
        end
        { items: project.prioritized_scope(:memex_project_items).not_archived }
      end

      private

      def validate_input(project, item, after = nil)
        raise Errors::Validation.new("The item does not exist in the project") if project.memex_project_items.find_by(id: item.id).nil?
        raise Errors::Validation.new("The item is archived and cannot be updated") unless item.archived_at.nil?
        return if after.nil?

        raise Errors::Validation.new("The item to be positioned after does not exist in the project") if project.memex_project_items.find_by(id: after.id).nil?
        raise Errors::Validation.new("The item to be positioned after is archived and cannot be used to update the position of this item") unless after.archived_at.nil?
      end
    end
  end
end
