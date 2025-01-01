# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ClosedIssueNextComponent < ApplicationComponent
      include FeedCards::IssueViewComponentMethods

      def heading_icon
        { name: :"feed-issue-closed", exported: true }
      end
    end
  end
end
