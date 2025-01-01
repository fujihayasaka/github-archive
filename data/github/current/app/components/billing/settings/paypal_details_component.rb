# typed: true
# frozen_string_literal: true

class Billing::Settings::PaypalDetailsComponent < ApplicationComponent
  # payment_method - a PaymentMethod
  def initialize(payment_method:)
    @payment_method = payment_method
  end

  private

  attr_reader :payment_method

  def render?
    GitHub.billing_enabled? && logged_in? && payment_method.present? && payment_method.paypal?
  end
end
