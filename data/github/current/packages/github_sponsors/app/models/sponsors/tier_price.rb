# typed: true
# frozen_string_literal: true

# Note: This wraps a Billing::PlanChange, which
# is a transient object that is 100% dependent on `tier`.
# Does not apply to tier selection partial.
#
# Calculate a potential plan by adding `tier` to the current sponsor's
# existing subscription items
#
# It's not considered a plan change when the selected tier is equal to the
# current tier

module Sponsors
  class TierPrice
    class ListingMismatchError < StandardError; end

    include Billing::ProrationMath
    include GitHub::Memoizer

    # Public: Get the price the sponsor will be charged for the new tier.
    #
    # inputs - a Hash with the following keys:
    #   :sponsor - a User or Organization purchasing a sponsorship
    #   :new_tier - The SponsorsTier the sponsor is purchasing
    #   :prorated - Boolean representing whether the sponsor should pay a prorated amount based on their
    #               billing cycle (true), versus paying the full amount (false)
    #   :current_tier - The existing SponsorsTier from the sponsor for the same sponsorable
    #                   as the new tier, if one exists
    #
    # Returns a Billing::Money (may be Billing::Money.zero). Can raise
    # Sponsors::TierPrice::ListingMismatchError.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(sponsor:, new_tier:, prorated: true, current_tier: nil, exclude_fees: false)
      @sponsor = sponsor
      @new_tier = new_tier
      @prorated = prorated
      @current_tier = current_tier
      @exclude_fees = exclude_fees

      validate_tiers
    end

    def call
      exclude_fees ? price_excluding_fee : price_with_fee
    end

    private

    attr_reader :sponsor, :new_tier, :prorated, :current_tier, :exclude_fees

    def price_with_fee
      price_excluding_fee + Sponsorship.fee_at_sponsorship_payment_time_for(sponsor: @sponsor, flat_price: price_excluding_fee)
    end

    def price_excluding_fee
      return one_time_tier_price if new_tier.one_time?
      recurring_tier_price(prorated: prorated)
    end

    def validate_tiers
      return unless current_tier

      if current_tier.sponsors_listing_id != new_tier.sponsors_listing_id
        raise ListingMismatchError, "Current and new tier must be for the same listing"
      end
    end

    def one_time_tier_price
      Billing::Money.new(new_tier.monthly_price_in_cents)
    end

    def recurring_tier_price(prorated:)
      return Billing::Money.zero unless price_difference.positive?

      if prorated
        prorate(price_difference, service_percent_remaining)
      else
        price_difference
      end
    end

    def service_percent_remaining
      return 1 unless sponsor.next_sponsors_billing_date > GitHub::Billing.today

      service_duration_in_days = if sponsor.yearly_sponsors_plan?
        12.months / 1.day
      else
        1.month / 1.day
      end

      service_days_remaining = sponsor.next_sponsors_billing_date - GitHub::Billing.today - 1

      service_percent_remaining = service_days_remaining / service_duration_in_days
      service_percent_remaining.clamp(0, 1)
    end

    memoize def price_difference
      current_renewal_price = if current_tier&.recurring?
        current_tier.renewal_price(sponsor: sponsor)
      else
        Billing::Money.zero
      end

      new_tier.renewal_price(sponsor: sponsor) - current_renewal_price
    end
  end
end
