# typed: true
# frozen_string_literal: true

class Billing::Settings::CardDetailsComponent < ApplicationComponent
  # payment_method - a PaymentMethod
  def initialize(payment_method:)
    @payment_method = payment_method
  end

  private

  def render?
    GitHub.billing_enabled? && logged_in? && @payment_method.present? && @payment_method.credit_card?
  end

  def credit_card
    @payment_method
  end
end
