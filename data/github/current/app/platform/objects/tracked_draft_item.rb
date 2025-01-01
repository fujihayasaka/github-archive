# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TrackedDraftItem < Platform::Objects::Base
      # This is a GraphQL object type that represents a draft item in a tracking block.
      # Tracked draft items are not backed by a database model, but are instead coming from issues-graph
      # Their permissions checks are already performed by the tracking issue
      description "A draft item in a tasklist block"

      visibility :internal

      def self.async_api_can_access?(permission, draft_issue)
        parent_issue = ::Issue.find_by(id: draft_issue.parent_issue.issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        permission.typed_can_access?("Issue", parent_issue)
      end

      def self.async_viewer_can_see?(permission, draft_issue)
        parent_issue = ::Issue.find_by(id: draft_issue.parent_issue.issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        permission.typed_can_see?("Issue", parent_issue)
      end

      field :title, String, null: false, description: "The string value of the item that is tracked"
      def title
        object.draft_issue
      end

      field :title_html, String, null: false, description: "The computed html value of the item's title"
      field :owner_id, ID, null: false, description: "The id of the owner of the tracking issue of the draft item - user or org"
      field :closed, Boolean, null: false, description: "Whether the draft item is completed"
      field :position, Integer, null: false, description: "The position of the item in the tracking block"
      field :uuid, ID, null: false, description: "The unique identifier of the tracked draft item as returned by issues graph"
    end
  end
end
