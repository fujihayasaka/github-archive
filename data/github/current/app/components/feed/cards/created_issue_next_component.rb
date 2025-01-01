# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class CreatedIssueNextComponent < ApplicationComponent
      include FeedCards::IssueViewComponentMethods

      def heading_icon
        { name: :"feed-issue-open", color: :open }
      end
    end
  end
end
