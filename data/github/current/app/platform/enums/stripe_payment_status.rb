# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class StripePaymentStatus < Platform::Enums::Base
      description "The status of the payment"

      # Source: https://stripe.com/docs/api/charges/object#charge_object-status
      value "SUCCEEDED", "Payment succeeded", value: "succeeded"
      value "PENDING", "Payment pending", value: "pending"
      value "FAILED", "Payment failed", value: "failed"
    end
  end
end
