# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2Item < Platform::Objects::Base
      model_name "MemexProjectItem"
      description "An item within a Project."

      visibility :public, environments: [:dotcom, :enterprise]

      PREFIX = Helpers::ProjectV2::Prefix.new("PVTI", :opvti, :upvti)
      implements_node templates: [
        [PREFIX.org, :owner_id, :project_id, :id],
        [PREFIX.user, :owner_id, :project_id, :id]
      ],
      as: PREFIX.to_s,
      ready_date: "1970-01-01" do |project_item|
        project_item.async_memex_project.then do |project|
          prefix = case project.owner_type
          when "Organization"
            PREFIX.org
          when "User"
            PREFIX.user
          else
            raise Platform::Errors::Internal, "Unexpected project owner: #{project.owner_type.inspect}"
          end
          {
            prefix: prefix,
            owner_id: project.owner_id,
            project_id: project.id,
            id: project_item.id
          }
        end
      end

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
      end

      def self.async_viewer_can_see?(permission, object)
        # ProjectV2Item can be accessed as long as the user can access the project, and the
        # item content is not spammy.
        object.async_memex_project.then do |project|
          can_see_project = permission.typed_can_see?("ProjectV2", project)

          object.async_spammy_by_viewer?(permission.viewer).then do |spammy|
            next false if spammy
            can_see_project
          end
        end
      end

      minimum_accepted_scopes ["read:project"]

      field :project, Platform::Objects::ProjectV2, description: "The project that contains this item.", null: false, method: :async_memex_project

      DeprecationNotice = {
        start_date: Date.new(2024, 10, 1),
        reason: "`databaseId` will be removed because it does not support 64-bit signed integer identifiers.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "dewski",
      }

      database_id_field(deprecated: DeprecationNotice)

      full_database_id_field

      created_at_field

      updated_at_field

      field :content, Unions::ProjectV2ItemContent, description: "The content of the referenced draft issue, issue, or pull request", null: true
      def content
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          next nil unless can_read

          if @object.draft_issue?
            @object.async_draft_issue
          else
            @object.async_issue_or_pull.then do |issue_or_pull|
              issue_or_pull.async_user.then { |user| user&.spammy? && user != @context[:viewer] ? nil : issue_or_pull }
            end
          end
        end
      end

      field :field_values, Connections.define(Unions::ProjectV2ItemFieldValue), "The field values that are set on the item.", connection: true, null: false, numeric_pagination_enabled: true do
        argument :order_by,
          Inputs::ProjectV2ItemFieldValueOrder,
          "Ordering options for project v2 item field values returned from the connection",
          required: false,
          default_value: {
            field: "position",
            direction: "ASC"
          }
      end
      def field_values(order_by:)
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          next ArrayWrapper.new([]) unless can_read

          Platform::Helpers::ProjectV2ItemFieldValue
            .async_refine_item_values(@object, @context[:viewer], @context[:cap_filter])
            .then { |values|  Platform::Helpers::ProjectV2.order_objects(values, order_by, omit_ordering: true) }
        end
      end

      field :field_value_by_name, Unions::ProjectV2ItemFieldValue, "The field value of the first project field which matches the 'name' argument that is set on the item.", null: true do
        argument :name, String, "The name of the field to return the field value of", required: true
      end
      def field_value_by_name(name:)
        return nil if name.blank?

        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          next unless can_read

          Platform::Helpers::ProjectV2ItemFieldValue
            .async_refine_item_values(
              @object,
              @context[:viewer],
              @context[:cap_filter],
              field_name: name
            ).then { |values| values.first }
        end
      end

      field :creator, Interfaces::Actor, description: "The actor who created the item.", null: true
      def creator
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          next nil unless can_read

          @object.async_creator
        end
      end

      field :is_archived, Boolean, description: "Whether the item is archived.", null: false, method: :archived?

      field :type, Platform::Enums::ProjectV2ItemType, description: "The type of the item.", null: false
      def type
        @object.async_readable_by_viewer?(@context[:viewer]).then do |can_read|
          next MemexProjectItem::REDACTED_ITEM_TYPE unless can_read

          @object.content_type
        end
      end
    end
  end
end
