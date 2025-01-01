# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StripeCharge < Platform::Objects::Base
      description "Stripe object created to charge a credit or debit card"
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
      # The documentation for it can be found here: https://stripe.com/docs/api/charges
      field :id, String, "Unique identifier for the charge", null: false

      field :amount, Integer, "Amount in the smallest currency unit intended to be collected by the payment", null: false

      field :balance_transaction, String, "Id of the balance transaction that describes the impact of this charge on the user's account balance", null: false

      field :created, Integer, "Time at which the chage was created, measured in seconds since the Unix epoch", null: false

      field :currency, String, "ISO currency code", null: false

      field :customer, String, "Id of the customer this charge", null: true

      field :description, String, "Arbitrary string attached to the charge", null: false

      field :disputed, Boolean, "Whether the charge has been disputed", null: false

      field :failure_code, String, "Error code explaining reason for charge failure", null: true

      field :failure_message, String, "Message to the user explaining details for charge failure", null: true

      field :invoice, String, "Id of the invoice this charge is for if it exists", null: true

      field :payment_intent, Objects::StripePaymentIntent, "Id of the payment intent associated with this charge", null: true
      def payment_intent
        Stripe::PaymentIntent.retrieve(@object[:payment_intent])
      end

      field :payment_method, String, "Id of payment method used", null: false

      field :receipt_email, String, "Email address of the customer for this charge", null: false

      field :refunded, Boolean, "Whether the charge has been refunded, if the charge is partially refunded, this will be false", null: false

      field :status, Enums::StripePaymentStatus, "Status of the charge", null: false

      field :metadata_z_payment_number, String, "Zuora payment number from metadata", null: true
      def metadata_z_payment_number
        @object[:metadata][:zpayment_number]
      end
    end
  end
end
