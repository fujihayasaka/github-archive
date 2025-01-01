# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextItemFieldValue < Platform::Objects::Base
      model_name "MemexProjectColumnValue"
      description "An value of a field in an item of a new Project."

      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        object.async_memex_project_item.then do |project_item|
          permission.typed_can_access?("ProjectNextItem", project_item).then do |can_access|
            next false unless can_access

            project_item.async_readable_by_viewer?(permission.viewer)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_memex_project_item.then do |project_item|
          permission.typed_can_see?("ProjectNextItem", project_item).then do |can_access|
            next false unless can_access

            project_item.async_readable_by_viewer?(permission.viewer)
          end
        end
      end

      minimum_accepted_scopes ["read:org"]

      implements_node templates: [[:opnipnif, :org_id, :project_next_item_id, :project_next_item_field_value_id]], as: "PNIFV", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |project_next_item_field_value|
        project_next_item_field_value.async_memex_project_item.then do |project_next_item|
          project_next_item.async_memex_project.then do |project|
            {
              prefix: :opnipnif,
              org_id: project.owner_id,
              project_next_item_id: project_next_item_field_value.memex_project_item_id,
              project_next_item_field_value_id: project_next_item_field_value.id
            }
          end
        end
      end

      field :project_field, Platform::Objects::ProjectNextField,  description: "The project field that contains this value.", null: false
      def project_field
        Loaders::ActiveRecord.load(::MemexProjectColumn, @object.memex_project_column_id)
      end

      field :project_field_constraint, Platform::Unions::ProjectNextFieldConfiguration,  description: "The project field that contains this value and it's constraint.", null: false
      def project_field_constraint
        @object.async_memex_project_item.then do |project_next_item|
          project_next_item.async_memex_project.then do |project|
            project.async_owner.then do |owner|
              Loaders::MemexProjectColumn.load(
                project,
                owner,
                @context[:viewer],
                @object.memex_project_column_id,
                v2: false
              )
            end
          end
        end
      end

      field :project_item, Platform::Objects::ProjectNextItem,  description: "The project item that contains this value.", null: false
      def project_item
        Loaders::ActiveRecord.load(::MemexProjectItem, @object.memex_project_item_id)
      end

      database_id_field

      created_at_field

      updated_at_field

      field :value, String, description: "The value of a field", null: true, method: :value

      field :creator, Interfaces::Actor, description: "The actor who created the item.", null: true, method: :async_creator
    end
  end
end
