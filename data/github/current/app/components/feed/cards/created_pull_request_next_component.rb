# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class CreatedPullRequestNextComponent < PullRequestBaseComponent
      HEADING_ICON = { name: :"feed-pull-request-open", color: :open }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
