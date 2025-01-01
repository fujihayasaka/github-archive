# typed: true
# frozen_string_literal: true

# Public: A representation of the sponsorships scheduled to be charged in a
#         given month
module Sponsors
  class SponsorshipCommitment
    # months_from_now - Integer: the number of months from the current date that is
    #                   being calculated
    # sponsorships    - Array of Sponsorships: active sponsorships for the given organization
    # bill_cycle_day  - Integer: number between 1-31 on which the customer is billed each month
    def initialize(months_from_now:, sponsorships:, bill_cycle_day:)
      @months_from_now = months_from_now
      @sponsorships = sponsorships
      @bill_cycle_day = bill_cycle_day
      @today = Date.current
    end

    attr_reader :months_from_now

    # Public: The total cost in cents of each sponsorship that will be charged
    #         in a given month
    #
    # Returns Integer
    def price_in_cents
      @price_in_cents ||= calculate_total_price
    end

    private

    # Private: Calculate how much the customer should be charged this month
    #
    # Automatically return 0 if this month represents the current month, and
    # their billing cycle date has passed. Otherwise, add together the prices of
    # each of the sponsorships to be paid this month.
    #
    # Returns Integer
    def calculate_total_price
      return 0 if has_already_been_paid?
      sponsorships_for_month.sum(&:monthly_price_in_cents)
    end

    # Private: All of the sponsorships that will be charged in a given month.
    #          This includes sponsorships that don't expire, and sponsorships that expire
    #          after the given month.
    #
    # Returns Array of Sponsorships
    def sponsorships_for_month
      @sponsorships_for_month ||= @sponsorships.filter { |s| to_be_paid? s }
    end

    # Private: Will this sponsorship be charged for this month?
    #
    # Sponsorship will be charged if:
    #   - it has not expired
    #   - it won't have expired by this month
    #   - it has not already been paid this month
    #
    # Returns Boolean
    def to_be_paid?(sponsorship)
      return true if sponsorship.expires_at.nil? && sponsorship.active?
      return false if has_already_been_paid?

      sponsorship.expires_at > @today
    end

    # Private: Have sponsorships for this month already been paid
    #
    # True if this commitment is for the current month and
    # the billing cycle day has already passed
    #
    # Returns Boolean
    def has_already_been_paid?
      months_from_now == 0 && @bill_cycle_day <= @today.day
    end
  end
end
