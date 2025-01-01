# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class PotentialSponsorshipListItemComponent < ApplicationComponent
      # potential_sponsorship - a PotentialSponsorship
      def initialize(potential_sponsorship:)
        @potential_sponsorship = potential_sponsorship
      end

      private

      attr_reader :potential_sponsorship

      delegate :potential_sponsorable, :potential_sponsor, to: :potential_sponsorship

      def render?
        potential_sponsorship && GitHub.sponsors_enabled? && logged_in?
      end

      def edit_url
        edit_stafftools_user_potential_sponsorship_path(potential_sponsorable, potential_sponsorship)
      end

      def delete_url
        stafftools_user_potential_sponsorship_path(potential_sponsorable, potential_sponsorship)
      end

      def potential_sponsorable_url
        if potential_sponsorable.sponsors_listing
          stafftools_sponsors_member_path(potential_sponsorable)
        else
          stafftools_user_path(potential_sponsorable)
        end
      end

      def potential_sponsor_url
        if potential_sponsorship.sponsorship_created?
          billing_stafftools_user_path(potential_sponsor, anchor: "current-sponsorships")
        else
          stafftools_user_path(potential_sponsor)
        end
      end

      def icon
        if potential_sponsorship.pending?
          :"dot-fill"
        elsif potential_sponsorship.acknowledged?
          :"x-circle"
        elsif potential_sponsorship.sponsors_listing_created?
          :heart
        elsif potential_sponsorship.sponsorship_created?
          :"heart-fill"
        end
      end

      def icon_color
        if potential_sponsorship.acknowledged?
          :subtle
        else
          state_scheme
        end
      end

      def state_scheme
        if potential_sponsorship.pending?
          :attention
        elsif potential_sponsorship.acknowledged?
          :secondary
        elsif potential_sponsorship.sponsors_listing_created?
          :success
        elsif potential_sponsorship.sponsorship_created?
          :sponsors
        end
      end
    end
  end
end
