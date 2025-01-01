# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class PrivateToPublicRepositoryNextComponent < ApplicationComponent
      include FeedCards::RepositoryViewComponentMethods

      HEADING_ICON = { name: :"feed-public", color: :muted, exported: true }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
