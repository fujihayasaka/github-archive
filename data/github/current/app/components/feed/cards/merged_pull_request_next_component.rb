# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class MergedPullRequestNextComponent < ApplicationComponent
      include FeedCards::PullRequestViewComponentMethods

      HEADING_ICON = { name: :"feed-merged", color: :done }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
