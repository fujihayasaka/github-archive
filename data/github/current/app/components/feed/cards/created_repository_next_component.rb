# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class CreatedRepositoryNextComponent < ApplicationComponent
      include FeedCards::RepositoryViewComponentMethods

      HEADING_ICON = { name: :"feed-repo", color: :muted }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
