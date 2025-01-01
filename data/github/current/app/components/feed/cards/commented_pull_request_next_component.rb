# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class CommentedPullRequestNextComponent < CommentBaseComponent
      HEADING_ICON = { name: :"feed-discussion", color: :done }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
