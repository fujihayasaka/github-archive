# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class PotentialSponsorshipsListComponent < ApplicationComponent
      # potential_sponsorships - a WillPaginate::Collection of PotentialSponsorship
      def initialize(potential_sponsorships:)
        @potential_sponsorships = potential_sponsorships
      end

      private

      def render?
        !@potential_sponsorships.nil? && GitHub.sponsors_enabled? && logged_in?
      end

      memoize def potential_sponsorships
        GitHub::PrefillAssociations.prefill_associations(@potential_sponsorships, [:potential_sponsor,
          :potential_sponsorable, :created_by])
        potential_sponsorables = @potential_sponsorships.map(&:potential_sponsorable)
        users = (
          @potential_sponsorships.map(&:potential_sponsor) +
          potential_sponsorables +
          @potential_sponsorships.map(&:created_by)
        ).uniq
        GitHub::PrefillAssociations.prefill_associations(users, :profile)
        GitHub::PrefillAssociations.prefill_associations(potential_sponsorables, :sponsors_listing)
        @potential_sponsorships
      end
    end
  end
end
