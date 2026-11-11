# typed: strict
# frozen_string_literal: true

module Billing::PricingDisplay
  extend ActiveSupport::Concern
  extend T::Helpers

  # Data structure for displaying product pricing with discount information in views.
  class PricingData < T::Struct
    const :original_price, Billing::Money
    const :discounted_price, Billing::Money
    const :discount_amount, Billing::Money
    const :has_coupon, T::Boolean
    const :coupon, T.nilable(Coupon)
    const :billing_cycle, String
    const :is_percentage_discount, T::Boolean
    const :discount_percentage, T.nilable(Integer)

    sig { returns(String) }
    def formatted_original_price
      original_price.format(no_cents_if_whole: false)
    end

    sig { returns(String) }
    def formatted_discounted_price
      discounted_price.format(no_cents_if_whole: false)
    end

    sig { returns(String) }
    def formatted_discount_amount
      discount_amount.format(no_cents_if_whole: false)
    end

    sig { returns(String) }
    def billing_period_label
      billing_cycle == "monthly" ? "mo" : "yr"
    end

    sig { returns(String) }
    def discount_label
      if is_percentage_discount && discount_percentage
        "#{discount_percentage}% off"
      else
        "#{formatted_discount_amount} off"
      end
    end
  end
end
