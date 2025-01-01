# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class StarredRepositoryComponent < RepoBaseComponent
      HEADING_ICON = { name: :"feed-star", color: :attention }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
