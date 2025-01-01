# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class NearSponsorsGoalComponent < UserBaseComponent
      HEADING_ICON = { name: :"feed-heart", color: :sponsors }.freeze

      private

      def render?
        return false unless item.render?
        return false unless user.present?

        GitHub.sponsors_enabled? &&
          sponsors_listing.presence &&
          sponsors_goal.presence &&
          sponsors_goal.near_complete?
      end

      def heading_icon
        HEADING_ICON
      end

      memoize def description
        sponsors_goal.description
      end

      def render_sponsor_button?
        user.sponsorable?
      end
    end
  end
end
