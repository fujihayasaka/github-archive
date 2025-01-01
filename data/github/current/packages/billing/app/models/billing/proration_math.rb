# typed: true
# frozen_string_literal: true

module Billing
  module ProrationMath

    # Public: Prorate the given amount for a percentage of a service period.
    # Truncates fractional cents, similar to Braintree and Zuora
    #
    # amount     - Money amount for full service period.
    # percentage - Float percentage of period to prorate for.
    #
    # Returns a Money prorated amount.
    def prorate(amount, percentage)
      Billing::Money.new((amount.cents * percentage).to_i)
    end
  end
end
