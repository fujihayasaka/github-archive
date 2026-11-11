# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class DisableMatchForSponsorsComponent < ApplicationComponent
      include AvatarHelper

      def initialize(sponsors_listing:)
        @sponsors_listing = sponsors_listing
      end

      private

      attr_reader :sponsors_listing

      delegate :sponsorable_login, to: :sponsors_listing

      def render?
        return false unless sponsors_listing
        return false if sponsors_listing.for_organization?
        return false if sponsors_listing.match_disabled?
        sponsors_listing.joined_waitlist_before_match_deadline?
      end

      memoize def sponsorship_match_bans
        sponsors_listing.sponsorship_match_bans.includes(:sponsor).to_a
      end
    end
  end
end
