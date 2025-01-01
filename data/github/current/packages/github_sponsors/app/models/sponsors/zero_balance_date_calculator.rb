# typed: true
# frozen_string_literal: true

# Public: Calculates when a given invoiced customer will use their entire credit
#         balance according to their active recurring sponsorships
module Sponsors
  class ZeroBalanceDateCalculator
    include GitHub::Memoizer
    # sponsorships    - a collection of Sponsorships for a given invoiced customer
    # current_balance - a Billing::Money object
    # customer        - a Customer with purpose=sponsors
    def initialize(sponsorships:, current_balance:, customer:)
      @sponsorships = sponsorships
      @current_balance = current_balance
      @customer = customer
      @today = Date.current
    end

    # Public: The date that the sponsor's balance will reach zero.
    #
    # If the sponsor is billed on a day that does not exist in every month (eg, the
    # 31st), round down to the end of the month
    #
    # Returns Date or Nil
    def zero_balance_date
      return nil unless calculable?
      return end_of_last_covered_month if invalid_billing_date_for_final_month?
      last_billing_date
    end

    # Public: Are we able to calculate the zero balance date for this sponsor?
    #
    # False if there are no active sponsorships.
    # False if they will not run out of sponsorships within a year
    # False if their balance is currently zero
    # True  if their current balance in greater than 0
    #
    # Returns Boolean
    def calculable?
      return false unless @sponsorships.any?
      return false unless will_exhaust_balance_within_year?
      @current_balance.positive?
    end

    # Public: How much money will be left in their balance after as many as
    #         commitments as possible have been covered
    #
    # Particularly useful when they don't have enough money to cover another
    # sponsorship, but their balance is still greater than zero
    #
    # Returns Integer
    def remaining_balance
      return @current_balance.cents if number_of_months_from_now_covered.zero?
      @current_balance.cents - commitment_through(number_of_months_from_now_covered)
    end

    private

    # Private: Will the sponsor use all of their funds within a year?
    #
    # Returns Boolean
    def will_exhaust_balance_within_year?
      annual_commitment >= @current_balance.cents
    end

    # Private: How much money is the sponsor currently committed to spending in
    #          within the next 12 months?
    #
    # Returns Integer
    def annual_commitment
      @annual_commitment ||= commitment_through(11)
    end

    # Private: The last day of the last month that will be covered by the
    #          sponsor's credit balance
    #
    # Returns Date
    def end_of_last_covered_month
      (@today + number_of_months_from_now_covered.months).end_of_month
    end

    # Private: The date of the last billing cycle that will be covered by the
    #          sponsor's credit balance
    #
    # Returns Date
    def last_billing_date
      Date.new(zero_balance_date_year, zero_balance_date_month, bill_cycle_day)
    end

    # Private: Is the customer's billing date valid for the month their
    #          balance will reach zero?
    #
    # Useful for cases where the customer's billing day does not exist in every
    # month, such as the 29th, 30th, and 31st in February.
    #
    # Returns Boolean
    def invalid_billing_date_for_final_month?
      valid_days = Time.days_in_month(zero_balance_date_month, zero_balance_date_year)
      bill_cycle_day > valid_days
    end

    # Private: The month of the date where the sponsor's balance will run out
    #
    # Returns Integer
    def zero_balance_date_month
      (@today + number_of_months_from_now_covered.months).month
    end

    # Private: The year of the date where the sponsor's balance will run out
    #
    # Returns Integer
    def zero_balance_date_year
      (@today + number_of_months_from_now_covered.months).year
    end

    # Private: The number of months from today's date where all of the
    #          scheduled sponsorships can be paid from their current balance
    #
    # Returns Integer between 0 and 11
    memoize def number_of_months_from_now_covered
      sponsorship_commitment = commitments_by_month
        .reverse
        .find { |c| commitment_through(c.months_from_now) <= @current_balance.cents }
      sponsorship_commitment&.months_from_now || 0
    end

    # Private: The total cost of all sponsorships scheduled between today and a
    #         given number of months from now.
    #
    # month_number - Integer: The last month to be included in the sum
    #
    # Returns Integer
    def commitment_through(month_number)
      commitments_by_month
        .filter { |c| c.months_from_now <= month_number }
        .sum(&:price_in_cents)
    end

    # Private: creates an array of SponsorshipCommitments for each of the next
    #          12 months
    #
    # Returns an Array of Sponsors::SponsorshipCommitments
    memoize def commitments_by_month
      (0..11).map do |number|
        Sponsors::SponsorshipCommitment.new(
          months_from_now: number,
          sponsorships: @sponsorships,
          bill_cycle_day: bill_cycle_day
        )
      end
    end

    # Private: The day of the month that a customer is billed for their sponsorships
    #
    # Returns 1 in cases where the billing day is zero or nil
    #
    # Returns Number between 1-31
    def bill_cycle_day
      return @bill_cycle_day if defined?(@bill_cycle_day)
      @bill_cycle_day = if @customer.bill_cycle_day.nil? || @customer.bill_cycle_day.zero?
        1
      else
        @customer.bill_cycle_day
      end
    end
  end
end
