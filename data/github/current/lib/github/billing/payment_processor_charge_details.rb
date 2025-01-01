# typed: true
# frozen_string_literal: true

module GitHub::Billing
  # An intermediary to hold basic information necessary to charge a payment method. This
  # is translated to the processor's specific parameters.
  class PaymentProcessorChargeDetails < PaymentProcessorAdapter

    DOMAIN = "github.com"

    # Public: The payment token of the payment method
    attr_accessor :token

    # Public: The amount to charge in USD cents
    attr_accessor :amount_in_cents

    # Public: The user_id of the User being charged
    attr_accessor :user_id

    # Public: A description of the charge
    attr_accessor :description

    # Public: Amount in USD to two decimal places.
    #
    # Returns a String of the amount
    def amount
      Billing::Money.new(amount_in_cents, "USD").to_s
    end

    # Public: Domain of the product we're charging for.
    #
    # Returns a String
    def domain
      DOMAIN
    end

    # Billing descriptor URL.
    def contact_url
      ""
    end
  end
end
