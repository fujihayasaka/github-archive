# typed: true
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class CurrentTierComponent < ApplicationComponent
      def initialize(sponsorship:, sponsorable_metadata: nil, sponsors_listing:)
        @sponsorship = sponsorship
        @sponsorable_metadata = sponsorable_metadata || {}
        @sponsors_listing = sponsors_listing
      end

      private

      delegate :repository, to: :tier

      def render?
        logged_in? && @sponsorship.present? && !@sponsorship.patreon?
      end

      def show_edit_link?
        !pending_change? && sponsor_can_change_tiers?
      end

      def sponsor_can_change_tiers?
        !@sponsorship.locked? && other_recurring_tiers_available?
      end

      def pending_change
        @sponsorship.pending_change
      end

      sig { returns T::Boolean }
      def pending_change?
        pending_change.present?
      end

      def sponsorable
        @sponsorship.sponsorable
      end

      def sponsor
        @sponsorship.sponsor
      end

      def tier
        @sponsorship.tier
      end

      def tier_has_welcome_message?
        tier.has_welcome_message?
      end

      memoize def other_recurring_tiers_available?
        @sponsors_listing.published_recurring_tier_count > 1
      end

      def header_css_classes
        if pending_change?
          "flash-warn"
        else
          "color-bg-default d-flex flex-items-center"
        end
      end
    end
  end
end
