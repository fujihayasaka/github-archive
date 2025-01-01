# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TrackedIssueCompletion < Platform::Objects::Base
      description "Completion state of issues tracked by an issue that is tracked in a tasklist block"

      def self.async_api_can_access?(permission, object)
        Loaders::ActiveRecord.load(::Issue, object.parent_issue.issue_id).then do |parent_issue|
          permission.typed_can_access?("Issue", parent_issue)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        Loaders::ActiveRecord.load(::Issue, object.parent_issue.issue_id).then do |parent_issue|
          permission.typed_can_see?("Issue", parent_issue)
        end
      end

      field :total, Integer, null: false, description: "Total number of items tracked by this issue"
      field :completed, Integer, null: false, description: "Number of completed items tracked by this issue"
    end
  end
end
