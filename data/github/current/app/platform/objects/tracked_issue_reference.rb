# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TrackedIssueReference < Platform::Objects::Base
      # This is a GraphQL object type that represents a reference to an issue in a tracking block.
      # Its permissions checks will be performed by the referenced issue
      description "A reference to an issue that is tracked in a tasklist block"

      visibility :internal

      def self.async_api_can_access?(permission, object)
        parent_issue = ::Issue.find_by(id: object.parent_issue.issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        permission.typed_can_access?("Issue", parent_issue)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        parent_issue = ::Issue.find_by(id: object.parent_issue.issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        permission.typed_can_see?("Issue", parent_issue)
      end

      field :issue, Platform::Objects::Issue, null: false, description: "The issue that is tracked"
      field :position, Integer, null: false, description: "The position of the item in the tracking block"
      field :uuid, ID, null: false, description: "The unique identifier of the tracked issue as returned by issues graph"
      field :completion, Platform::Objects::TrackedIssueCompletion, null: true, description: "The completion state of items tracked by the issue"
    end
  end
end
