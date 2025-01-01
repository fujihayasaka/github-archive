# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class ToggleMatchComponent < ApplicationComponent
      def initialize(sponsors_listing:)
        @sponsors_listing = sponsors_listing
      end

      private

      attr_reader :sponsors_listing

      delegate :sponsorable_login, to: :sponsors_listing

      def render?
        return false unless sponsors_listing
        return false if sponsors_listing.for_organization?
        sponsors_listing.joined_waitlist_before_match_deadline?
      end

      def match_enabled?
        !sponsors_listing.match_disabled?
      end

      def action
        match_enabled? ? "Disable" : "Enable"
      end

      def title
        "#{action} match globally"
      end

      def body
        "#{action} GitHub Sponsors matching for all sponsorships to this account."
      end

      def form_method
        match_enabled? ? :delete : :post
      end
    end
  end
end
