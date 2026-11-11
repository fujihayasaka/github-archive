# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ViewItem < Platform::Objects::Base
      description "Represents a ProjectV2Item within the context of a view."
      minimum_accepted_scopes ["read:org"]
      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.item.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectV2", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.item.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectV2", project)
        end
      end

      field :item, Objects::ProjectV2Item, "The project item", null: true

      field :position, Integer, "The position of the item", null: true

      # Stubbing this for now until we can safely remove it from the schema.
      # This field used to represent an item's ranking on a view but was sunset
      # due to its performance cost: all items needed to be loaded for ranking _before_
      # filtering and sorting.
      def position
        nil
      end

      field :sort_values, [Platform::Objects::ProjectV2ViewItemSortableValue], "The sorting values of the item", null: true

      def sort_values
        (object.sort_values || []).map { Platform::Models::ProjectV2ViewItemSortableValue.from_raw_value(_1) }
      end
    end
  end
end
