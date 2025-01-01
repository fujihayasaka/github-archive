# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StripeEarlyFraudWarning < Platform::Objects::Base
      description "Stripe early fraud warning related to payment charges"
      visibility :internal

      # This object has no mapping to the database and has no specific permissions.
      # It can be accessed and viewed if the parent object can,
      # so we just return `true` in the following two methods

      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      # Below is a non-exhaustive list of fields that are available for the Stripe charge object
      # The documentation for it can be found here: https://stripe.com/docs/api/radar/early_fraud_warnings
      field :id, String, "Unique identifier for the early fraud warning", null: false

      field :actionable, Boolean, "Actionable if it has not received a dispute and has not been fully refunded", null: false

      field :charge, Objects::StripeCharge, "The charge that this early fraud warning is for", null: false
      def charge
        Stripe::Charge.retrieve(@object[:charge])
      end

      field :created, Integer, "Time at which the early fraud warning was created, measured in seconds since the Unix epoch", null: false

      field :fraud_type, Enums::StripeFraudType, "Type of fraud labelled by the issuer", null: false

      field :livemode, Boolean, "True if the object exists in live mode, false if it exists in test mode", null: false

      field :payment_intent, Objects::StripePaymentIntent, "ID of the Payment Intent this early fraud warning is for", null: false
      def payment_intent
        Stripe::PaymentIntent.retrieve(@object[:payment_intent])
      end

    end
  end
end
