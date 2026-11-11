# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class PotentialSponsorshipFormComponent < ApplicationComponent
      # potential_sponsorship - a PotentialSponsorship, does not have to be saved yet
      # potential_sponsorable - a User or Organization who does not have a SponsorsListing
      def initialize(potential_sponsorship:, potential_sponsorable:)
        @potential_sponsorship = potential_sponsorship
        @potential_sponsorable = potential_sponsorable
      end

      private

      attr_reader :potential_sponsorship, :potential_sponsorable

      def render?
        potential_sponsorship && potential_sponsorable && GitHub.sponsors_enabled? && logged_in? &&
          potential_sponsorship.potential_sponsorable_id == potential_sponsorable.id
      end

      def form_url
        if potential_sponsorship.persisted?
          stafftools_user_potential_sponsorship_path(potential_sponsorable, potential_sponsorship)
        else
          stafftools_user_potential_sponsorships_path(potential_sponsorable)
        end
      end

      def submit_button_text
        if potential_sponsorship.persisted?
          "Update potential sponsorship"
        else
          "Encourage them to create a Sponsors profile"
        end
      end
    end
  end
end
