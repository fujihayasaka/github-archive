# typed: true
# frozen_string_literal: true

# Public: Temporary wrapper for a braintree transaction.
#
# DEPRECATION WARNING:
# This class is deprecated with the transition to Zuora. It should not be used
# for new integrations and may be removed in the near future.
class Billing::BraintreeTransaction
  attr_reader :transaction
  delegate :status_history, :customer_details, :settlement_batch_id,
    to: :transaction

  def initialize(transaction)
    @transaction = transaction
  end

  def to_s
    transaction.inspect
  end

  def type
    refund? ? "refund" : "sale"
  end

  def sale?
    transaction.type == "sale"
  end

  def refund?
    transaction.type == "credit"
  end

  def success?
    %w(settled settling submitted_for_settlement).include?(transaction.status)
  end

  def status
    transaction.status
  end

  def voided?
    transaction.status == "voided"
  end

  def amount
    Billing::Money.new(transaction.amount * 100, "USD").to_s
  end

  def amount_in_cents
    val = transaction.amount * 100
    val = -val if refund?
    val
  end

  def cc_number
    details = transaction.credit_card_details
    "#{details.bin.first}***********#{details.last_4}"
  end

  def transaction_id
    transaction.id
  end

  alias_method :id, :transaction_id

  def original_transaction_id
    transaction.refunded_transaction_id
  end

  def formatted_date
    date.strftime("%Y-%m-%d")
  end

  def base_url
    @base_url ||= Braintree::Configuration.instantiate.base_merchant_url
  end

  def url
    "#{base_url}/transactions/#{transaction_id}"
  end

  def date
    # .to_time converts from UTC to local time zone
    @date ||= transaction.created_at.to_time
  end

  def in_progress?
    date > 10.minutes.ago
  end

  def postal_code
    transaction.billing_details.postal_code
  end

  def region
    transaction.billing_details.region
  end

  def country
    transaction.billing_details.country_name
  end

  def country_code_alpha3
    transaction.billing_details.country_code_alpha3
  end

  def bank_identification_number
    transaction.credit_card_details.bin
  end

  def country_of_issuance
    transaction.credit_card_details.country_of_issuance
  end

  # Public: Last four digits of the credit card number.
  #
  # Returns a String.
  def last_four
    transaction.credit_card_details.last_4
  end

  def custom_fields
    transaction.custom_fields
  end

  def paypal_email
    details = transaction.paypal_details
    details.payer_email if details.token.present?
  end

  def paypal?
    paypal_email.present?
  end

  def credit_card?
    !paypal?
  end
end
