# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextItem < Platform::Objects::Base
      model_name "MemexProjectItem"
      description "An item within a new Project."

      required_capabilities [:mobile_only_schema_mask]

      implements_node templates: [[:opni, :org_id, :project_next_id, :project_next_item_id]], as: "PNI", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |project_next_item|
        project_next_item.async_memex_project.then do |project_next|
          {
            prefix: :opni,
            org_id: project_next.owner_id,
            project_next_id: project_next.id,
            project_next_item_id: project_next_item.id
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, project_item)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        project_item.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectNext", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, project_item)
        project_item.async_memex_project.then do |project|
          permission.typed_can_see?("ProjectNext", project)
        end
      end

      minimum_accepted_scopes ["read:org"]

      field :project, Platform::Objects::ProjectNext, description: "The project that contains this item.", null: false, method: :async_memex_project

      database_id_field

      created_at_field

      updated_at_field

      field :title, String, description: "The title of the item", null: true
      def title
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          if can_read
            if @object.draft_issue?
              @object.async_draft_issue.then do |referenced_draft_issue|
                next nil if referenced_draft_issue.nil?
                referenced_draft_issue.title
              end
            else
              @object.async_issue_or_pull.then do |referenced_issue_or_pull|
                next nil if referenced_issue_or_pull.nil?
                referenced_issue_or_pull.title
              end
            end
          else
            MemexProjectItem::ColumnDependency::REDACTED_ITEM_TITLE
          end
        end
      end

      field :content, Unions::ProjectNextItemContent, description: "The content of the referenced draft issue, issue, or pull request", null: true
      def content
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          next nil unless can_read
          if @object.draft_issue?
            @object.async_draft_issue
          else
            @object.async_issue_or_pull
          end
        end
      end

      field :field_values, Connections.define(Objects::ProjectNextItemFieldValue), "List of field values", connection: true, null: false, numeric_pagination_enabled: true
      def field_values
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          next ArrayWrapper.new([]) unless can_read

          @object.async_memex_project_column_values.then do |values|
            ArrayWrapper.new(values)
          end
        end
      end

      field :creator, Interfaces::Actor, description: "The actor who created the item.", null: true
      def creator
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          can_read ? @object.async_creator : nil
        end
      end

      field :is_archived, Boolean, description: "Whether the item is archived.", null: false, method: :archived?

      field :type, Platform::Enums::ProjectItemType, description: "The type of the item.", null: false
      def type
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          if can_read
            @object.content_type
          else
            MemexProjectItem::REDACTED_ITEM_TYPE
          end
        end
      end
    end
  end
end
