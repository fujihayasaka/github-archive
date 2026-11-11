# typed: true
# frozen_string_literal: true

module Sponsors
  class CalculateMatch
    def self.for(listing, sponsorship_amount:)
      new(listing, sponsorship_amount: sponsorship_amount).send(:match_in_cents)
    end

    private

    attr_reader :listing, :sponsorship_amount

    def initialize(listing, sponsorship_amount:)
      @listing = listing
      @sponsorship_amount = sponsorship_amount
    end

    def match_in_cents
      if !matchable?
        0
      elsif sponsorship_will_exceed_total_match_limit?
        amount_left_in_limit
      else
        sponsorship_amount
      end
    end

    def matchable?
      listing.matchable?
    end

    def amount_left_in_limit
      [::SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS - total_ledger_amount_in_cents, 0].max
    end

    def sponsorship_will_exceed_total_match_limit?
      total_ledger_amount_in_cents + sponsorship_amount >= ::SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS
    end

    def total_ledger_amount_in_cents
      return @_total_ledger_amount_in_cents if defined?(@_total_ledger_amount_in_cents)
      @_total_ledger_amount_in_cents = listing.total_match_in_cents
    end
  end
end
