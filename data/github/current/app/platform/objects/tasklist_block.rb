# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # This is a GraphQL object type that represents a tracking block.
    # Tracking blocks are not backed by a database model, but are instead coming from issues-graph
    # Their permissions checks should coincide with the permissions checks for the issue they are attached to.
    class TasklistBlock < Platform::Objects::Base
      description "A tasklist block inside an issue"

      visibility :internal

      field :uuid, ID, null: false, description: "The unique identifier of the tracking block as returned by issues graph"
      def uuid
        object.key.primary_key.uuid
      end

      field :name, String, null: false, description: "The name of the tracking block"

      field :order, Integer, null: false, description: "The order of the tracking block"

      field :items,
        resolver: Resolvers::TrackedItems,
        connection: true,
        description: "A list of items - issues and drafts - tracked inside the tracking block",
        visibility: {
          public: { environments: [:dotcom] },
          under_development: { environments: [:enterprise] },
        }

      def self.async_api_can_access?(permission, tracking_block)
        parent_issue = ::Issue.find_by(id: tracking_block.parent_issue.issue_id)
        permission.typed_can_access?("Issue", parent_issue)
      end

      def self.async_viewer_can_see?(permission, tracking_block)
        parent_issue = ::Issue.find_by(id: tracking_block.parent_issue.issue_id)
        permission.typed_can_see?("Issue", parent_issue)
      end
    end
  end
end
