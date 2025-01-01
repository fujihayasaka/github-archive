# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextViewItem < Platform::Objects::Base
      description "Represents a ProjectNextItem within the context of a view."
      minimum_accepted_scopes ["read:org"]
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        object.item.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectNext", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.item.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectNext", project)
        end
      end

      field :item, Objects::ProjectNextItem, "The project item", null: true

      field :position, Integer, "The position of the item", null: true

      # Stubbing this for now until we can safely remove it from the schema.
      # This field used to represent an item's ranking on a view but was sunset
      # due to its performance cost: all items needed to be loaded for ranking _before_
      # filtering and sorting.
      def position
        nil
      end
    end
  end
end
