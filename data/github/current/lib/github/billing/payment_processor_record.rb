# typed: true
# frozen_string_literal: true

module GitHub::Billing
  # A flattened record interface for the information we get back from a payment
  # processor for a customer including payment method (credit card) and address
  # information.
  class PaymentProcessorRecord < PaymentProcessorAdapter
    attr_accessor :customer_id
    attr_accessor :token
    attr_accessor :masked_number, :expiration_month, :expiration_year, :card_type
    attr_accessor :region, :postal_code, :country_code_alpha3
    attr_accessor :unique_number_identifier
    attr_accessor :paypal_email
  end
end
