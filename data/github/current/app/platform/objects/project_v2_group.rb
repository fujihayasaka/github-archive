# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2Group < Platform::Objects::Base
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

      field :view, Objects::ProjectV2View, "The view that the grouped view items belongs to", resolver_method: :view_value, null: false

      # This is a workaround for a bug introduced by the graphql-pro gem which add methods with the same name as this field
      def view_value
        object.view
      end

      field :title, String, "The title of the item field group", null: true

      field :field, Unions::ProjectV2FieldConfiguration, "The field that the item field group belongs to", null: true

      field :value, Unions::ProjectV2GroupValue, "The underlying value shared by all the items for the grouped field", null: true

      field :view_group_id, String, "Unique identifier for the group within a view.", null: true

      field :items,
        Connections::ProjectV2ViewItem,
        "Pageable items within a group.",
        null: false,
        extras: [:ast_node],
        connection: false do
        has_connection_arguments
      end

      def items(arguments)
        async_use_elasticsearch?.then do |use_elasticsearch|
          if use_elasticsearch
            ConnectionWrappers::ProjectV2ElasticsearchViewItems.new(object)
          else
            arguments[:project_group] = object
            ConnectionWrappers::ProjectV2ViewItems.new(
              nil,
              first: arguments[:first],
              last: arguments[:last],
              after: arguments[:after],
              before: arguments[:before],
              arguments:,
            )
          end
        end
      end

      private

      def async_use_elasticsearch?
        Helpers::Projects::Backend.async_use_elasticsearch?(
          memex_project_or_view: object.view,
        )
      end
    end
  end
end
