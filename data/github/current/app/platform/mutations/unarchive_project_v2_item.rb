# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnarchiveProjectV2Item < Platform::Mutations::Base
      description "Unarchives a ProjectV2Item"
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project to archive the item from.", required: true, loads: Objects::ProjectV2
      argument :item_id, ID, "The ID of the ProjectV2Item to unarchive.", required: true, loads: Objects::ProjectV2Item

      field :item, Objects::ProjectV2Item, "The item unarchived from the project.", null: true

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
          ) && item.async_readable_by_viewer?(permission.viewer)
        end
      end

      def resolve(project:, item:)
        item = project.memex_project_items.find_by(id: item.id)
        if item.nil?
          raise Errors::Validation.new("The item does not exist in the project.")
        end

        begin
          { item: item, errors: [] } if item.update!(archiver: nil, archived_at: nil)
        rescue ActiveRecord::RecordInvalid => e
          raise Errors::Unprocessable.new(e.message)
        end
      end
    end
  end
end
