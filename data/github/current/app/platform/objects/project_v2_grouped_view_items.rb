# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2GroupedViewItems < Platform::Objects::Base
      description "Represents a group of items within a ProjectV2View."
      minimum_accepted_scopes ["read:org"]
      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.view.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectV2", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.view.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectV2", project)
        end
      end

      field :view, Objects::ProjectV2View, "The view that the grouped view items belongs to", null: false

      field :group, Objects::ProjectV2ItemFieldGroup, "The group that the view items belong to", null: true

      field :view_items, [Objects::ProjectV2ViewItem], "The view items", null: true
    end
  end
end
