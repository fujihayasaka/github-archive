# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ClosedPullRequestNextComponent < ApplicationComponent
      include FeedCards::PullRequestViewComponentMethods

      HEADING_ICON = { name: :"feed-pull-request-closed", color: :closed }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
