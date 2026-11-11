# typed: true
# frozen_string_literal: true

class Billing::PaymentDetails
  def initialize(payment_details)
    @payment_details = payment_details
  end

  def valid?
    payment_details[:zuora_payment_method_id].present? || credit_card_details? || paypal_details?
  end

  def credit_card_details?
    payment_details[:credit_card] && payment_details[:credit_card][:cvv].present?
  end

  def paypal_details?
    payment_details[:paypal_nonce].present?
  end

  private

  attr_reader :payment_details
end
