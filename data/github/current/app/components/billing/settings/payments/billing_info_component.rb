# typed: true
# frozen_string_literal: true

class Billing::Settings::Payments::BillingInfoComponent < ApplicationComponent
  extend T::Sig

  sig { params(manual_payment: Billing::ManualPayment, trade_screening_needed: T::Boolean).void }
  def initialize(manual_payment:, trade_screening_needed:)
    @manual_payment = manual_payment
    @trade_screening_needed = trade_screening_needed
  end

  private

  attr_reader :manual_payment, :trade_screening_needed

  delegate :target, to: :manual_payment

  def render?
    return false unless GitHub.billing_enabled?

    manual_payment.single_payment?
  end
end
