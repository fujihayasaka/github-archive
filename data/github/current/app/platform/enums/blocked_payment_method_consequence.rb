# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class BlockedPaymentMethodConsequence < Platform::Enums::Base
      docs_category :billing
      description "The consequence applied when a payment method is blocked."
      visibility :internal

      value "SUSPENDED", "Suspend the account using the payment method", value: "suspended"
      value "BILLING_LOCKED", "Lock billing for the account using the payment method", value: "billing_locked"
    end
  end
end
