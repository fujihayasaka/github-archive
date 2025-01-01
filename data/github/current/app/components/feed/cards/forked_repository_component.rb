# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ForkedRepositoryComponent < RepoBaseComponent
      HEADING_ICON = { name: :"feed-forked", color: :muted }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
