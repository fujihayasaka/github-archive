# typed: true
# frozen_string_literal: true

class Billing::Settings::Payments::CreditCardFormComponent < ApplicationComponent
  include BillingSettingsHelper

  sig do
    params(
      manual_payment: Billing::ManualPayment,
      trade_screening_needed: T::Boolean,
      card_setup: T::Boolean,
      post_success_form_selector: T.nilable(String),
      failure_redirect_to: T.nilable(String),
    )
    .void
  end
  def initialize(manual_payment:, trade_screening_needed:, card_setup: false, post_success_form_selector: nil, failure_redirect_to: nil)
    @manual_payment = manual_payment
    @trade_screening_needed = trade_screening_needed
    @card_setup = card_setup
    @post_success_form_selector = post_success_form_selector
    @failure_redirect_to = failure_redirect_to
  end

  private

  attr_reader :manual_payment, :trade_screening_needed, :post_success_form_selector, :failure_redirect_to

  delegate :target, :purpose, to: :manual_payment

  def card_setup?
    @card_setup
  end

  def render?
    return false unless GitHub.billing_enabled?

    manual_payment.single_payment?
  end
end
