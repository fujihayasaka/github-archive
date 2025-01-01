# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectV2ItemFieldValueCommon
      include Platform::Interfaces::Base
      description "Common fields across different project field value types"

      visibility :public, environments: [:dotcom, :enterprise]

      database_id_field

      created_at_field

      updated_at_field

      field :id, ID, description: "The Node ID of the ProjectV2ItemFieldValueCommon object", method: :global_relay_id, null: false

      field :field, Platform::Unions::ProjectV2FieldConfiguration,  description: "The project field that contains this value.", null: false
      def field
        @object.async_memex_project_item.then do |project_next_item|
          project_next_item.async_memex_project.then do |project|
            project.async_owner.then do |owner|
              Loaders::MemexProjectColumn.load(
                project,
                owner,
                @context[:viewer],
                @object.memex_project_column_id
              )
            end
          end
        end
      end

      field :item, Platform::Objects::ProjectV2Item,  description: "The project item that contains this value.", null: false
      def item
        Loaders::ActiveRecord.load(::MemexProjectItem, @object.memex_project_item_id)
      end

      field :creator, Interfaces::Actor, description: "The actor who created the item.", null: true, method: :async_creator
    end
  end
end
