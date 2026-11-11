# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ReopenedIssueComponent < ApplicationComponent
      include FeedCards::IssueViewComponentMethods

      def heading_icon
        { name: :"feed-issue-reopen", color: :open }
      end
    end
  end
end
