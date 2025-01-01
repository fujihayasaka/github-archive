# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextItemFieldGroup < Platform::Objects::Base
      description "A group that an item belongs to, based on the view's group by field."
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
          permission.typed_can_see?("ProjectNext", project)
        end
      end

      field :title, String, "The title of the item field group", null: true

      field :view, Objects::ProjectView, "The view that the item field group belongs to", null: true

      field :field, Objects::ProjectNextField, "The field that the item field group belongs to", null: true
    end
  end
end
