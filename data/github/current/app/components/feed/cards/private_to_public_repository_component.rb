# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class PrivateToPublicRepositoryComponent < RepoBaseComponent
      HEADING_ICON = { name: :"globe", color: :muted }.freeze

      private

      def heading_icon
        HEADING_ICON
      end
    end
  end
end
