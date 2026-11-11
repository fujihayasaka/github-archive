# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ClosedIssueComponent < ApplicationComponent
      include FeedCards::IssueViewComponentMethods

      def heading_icon
        { name: :"feed-issue-closed", exported: true }
      end
    end
  end
end
