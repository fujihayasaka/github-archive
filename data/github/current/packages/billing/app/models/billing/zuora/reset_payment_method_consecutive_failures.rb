# typed: strict
# frozen_string_literal: true

module Billing
  module Zuora
    # Reset a Zuora payment method's number of consecutive failures to zero,
    # allowing the payment method to be charged
    #
    # This is primarily useful when manually resetting billing attempts in
    # Stafftools, since Zuora resets this automatically on successful payment
    class ResetPaymentMethodConsecutiveFailures
      extend T::Sig

      sig { returns(T.nilable(::PaymentMethod)) }
      attr_reader :payment_method

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      attr_reader :response

      # Initialize a new ResetPaymentMethodConsecutiveFailures
      sig { params(payment_method: T.nilable(::PaymentMethod)).void }
      def initialize(payment_method:)
        @payment_method = T.let(payment_method, T.nilable(::PaymentMethod))
        @response = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
      end

      # Reset the number of consecutive failures on the Zuora payment method
      sig { returns(T.self_type) }
      def perform
        payment_method = self.payment_method
        return self unless payment_method
        return self unless payment_method.on_zuora?

        @response = GitHub.zuorest_client.update_payment_method(
          payment_method.payment_token,
          "NumConsecutiveFailures" => 0,
        )
        self
      end

      # Whether or not the operation was successful
      sig { returns(T::Boolean) }
      def success?
        @response&.dig("Success") == true
      end
    end
  end
end
