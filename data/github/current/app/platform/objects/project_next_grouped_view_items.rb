# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextGroupedViewItems < Platform::Objects::Base
      description "Represents a group of items within a ProjectView."
      minimum_accepted_scopes ["read:org"]
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        object.view.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectNext", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.view.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectNext", project)
        end
      end

      field :view, Objects::ProjectView, "The view that the grouped view items belongs to", null: true

      field :group, Objects::ProjectNextItemFieldGroup, "The group that the view items belong to", null: true

      field :view_items, [Objects::ProjectNextViewItem], "The view items", null: true
    end
  end
end
