# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StripePaymentIntent < Platform::Objects::Base
      description "Stripe object that goes through the process of collecting a payment from a customer"
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
      # The documentation for it can be found here: https://stripe.com/docs/api/payment_intents
      field :id, String, "Unique identifier for the payment intent", null: false

      field :amount, Integer, "Amount intended to be collected by this PaymentIntent in the smallest currency unit", null: false

      field :charges, [Objects::StripeCharge], "Charges created by this PaymentIntent", null: false
      def charges
        Stripe::Charge.list({ payment_intent: @object[:id] })
      end

      field :client_secret, String, "Client secret of this PaymentIntent", null: false

      field :created, Integer, "Time at which the chage was created, measured in seconds since the Unix epoch", null: false

      field :currency, String, "ISO Currency code", null: false

      field :customer, String, "Id of the customer this charge", null: true

      field :description, String, "Arbitrary string attached to the charge", null: false

      field :receipt_email, String, "Email address of the customer for this charge", null: true

      field :payment_method, String, "Id of payment method used", null: false

      field :status, Enums::StripePaymentIntentStatus, "Status of the payment intent", null: false
    end
  end
end
