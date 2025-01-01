# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class StripePaymentIntentStatus < Platform::Enums::Base
      description "The status of the payment intent"

      # Source: https://stripe.com/docs/api/payment_intents/object#payment_intent_object-status
      value "SUCCEEDED", "Payment succeeded", value: "succeeded"
      value "CANCELED", "Payment canceled", value: "canceled"
      value "REQUIRES_PAYMENT_METHOD", "Requires a payment method", value: "requires_payment_method"
      value "REQUIRES_CONFIRMATION", "The state in which a customer provides payment information but has not confirmed payment intent", value: "requires_confirmation"
      value "REQUIRES_ACTION", "Payment requires additional actions, such as authenticating with 3D Secure", value: "requires_action"
      value "PROCESSING", "All required actions are fulfilled and the payment intent is processing", value: "processing"
      value "REQUIRES_CAPTURE", "Requires capture", value: "requires_capture"
    end
  end
end
