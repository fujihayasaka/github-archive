# typed: true
# frozen_string_literal: true

class Billing::Settings::Payments::CreditCardFormComponent < ApplicationComponent
  include BillingSettingsHelper

  sig do
    params(
      manual_payment: Billing::ManualPayment,
      trade_screening_needed: T::Boolean,
    )
    .void
  end
  def initialize(manual_payment:, trade_screening_needed:)
    @manual_payment = manual_payment
    @trade_screening_needed = trade_screening_needed
  end

  private

  attr_reader :manual_payment, :trade_screening_needed

  delegate :target, :purpose, to: :manual_payment

  def render?
    return false unless GitHub.billing_enabled?

    manual_payment.single_payment?
  end
end
