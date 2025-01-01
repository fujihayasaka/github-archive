# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ReopenedIssueNextComponent < ApplicationComponent
      include FeedCards::IssueViewComponentMethods

      def heading_icon
        { name: :"feed-issue-reopen", color: :open }
      end
    end
  end
end
