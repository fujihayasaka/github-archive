# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class NewlySponsorableNextComponent < BaseComponent
      HEADING_ICON = { name: :"feed-heart", color: :sponsors }.freeze

      private

      def render?
        return false unless user.present? && user.sponsorable?

        newly_sponsorable_action? && GitHub.sponsors_enabled?
      end

      def heading_icon
        HEADING_ICON
      end

      memoize def user
        item.subject
      end

      def user_name
        user.profile_name || user.display_login
      end

      memoize def description
        user.sponsors_bio_html
      end

      memoize def sponsoring?
        user.sponsored_by_viewer?(current_user)
      end

      def render_description?
        description.present?
      end

      memoize def newly_sponsorable_action?
        item.sponsorable_action?
      end

      def render_sponsor_button?
        user.sponsorable?
      end

      def using_profile_bio?
        user.sponsors_bio.blank?
      end

      def hydro_data(click_target:)
        helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
      end

      def sponsors_url
        "/sponsors/#{user.display_login}"
      end
    end
  end
end
