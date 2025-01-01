# typed: true
# frozen_string_literal: true

module GitHub::Billing
  # An interface object for updating or creating a customer record with payment
  # details in a payment processor's system.
  class PaymentProcessorPaymentDetails < PaymentProcessorAdapter
    # Public: String payment token.
    attr_reader :token

    # Credit/debit card information
    attr_reader :card_number, :expiration_month, :expiration_year, :cvv
    attr_reader :has_card_on_file

    # PayPal information
    attr_reader :paypal_nonce

    # Zuora HPM
    attr_reader :zuora_payment_method_id

    # Address information
    attr_reader :country_code_alpha3, :region, :postal_code

    # Additional meta data that maps to our user records
    attr_reader :user_id, :email, :login, :account_name

    # Whether Auto-Pay is enabled
    attr_reader :auto_pay

    # Public: Boolean if this is a request to update a credit card already on file.
    #
    # Returns truthy if an existing card should be updated (without updating the actual cc number).
    def update_card_on_file?
      !paypal? && !!has_card_on_file && card_number.blank?
    end

    # Public: Boolean if this record represents credit card details.
    def credit_card?
      !!cvv
    end

    # Public: Boolean if this record represents paypal account details.
    def paypal?
      braintree_paypal?
    end

    # Public: Boolean if this record represents a Zuora HPM Payment Method
    def zuora_hosted_payments_page_details?
      zuora_payment_method_id.present?
    end

    # Public: Boolean Braintree Paypal flow
    def braintree_paypal?
      paypal_nonce.present?
    end

    def zuora_payment_details?
      zuora_hosted_payments_page_details? || braintree_paypal?
    end
  end
end
