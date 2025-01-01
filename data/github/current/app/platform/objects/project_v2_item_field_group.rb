# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemFieldGroup < Platform::Objects::Base
      description "A group that an item belongs to, based on the view's group by field."
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
          permission.typed_can_see?("ProjectV2", project)
        end
      end

      field :title, String, "The title of the item field group", null: true

      field :view, Objects::ProjectV2View, "The view that the item field group belongs to", null: true

      field :field,
        Objects::ProjectV2Field,
        "The field that the item field group belongs to (Deprecated: use `ProjectV2ItemFieldGroup#groupByField` instead)",
        null: true,
        deprecated: {
          start_date: Date.new(2023, 1, 26),
          reason: "The `ProjectV2ItemFieldGroup#field` API is deprecated in favour of the more capable `ProjectV2ItemFieldGroup#groupByField` API.",
          superseded_by: "Check out the `ProjectV2ItemFieldGroup#groupByField` API as an example for the more capable alternative.",
          owner: "stevepopovich",
        }

      field :group_by_field, Unions::ProjectV2FieldConfiguration, "The field that the item field group belongs to", null: true
      def group_by_field
        @object.field
      end

      field :value, Unions::ProjectV2GroupValue, "The underlying value shared by all the items for the grouped field", null: true
    end
  end
end
