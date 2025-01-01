# typed: true
# frozen_string_literal: true

class Billing::Settings::Payments::SidebarComponent < ApplicationComponent
  extend T::Sig

  # manual_payment - Billing::ManualPayment describing the payment
  sig { params(manual_payment: Billing::ManualPayment).void }
  def initialize(manual_payment:)
    @manual_payment = manual_payment
  end

  private

  attr_reader :target, :manual_payment

  def render?
    GitHub.billing_enabled?
  end

  def total_balance_due
    manual_payment.balance_due
  end

  def general_balance_due
    manual_payment.balance_due(purpose: :general)
  end

  def sponsors_balance_due
    manual_payment.balance_due(purpose: :sponsors)
  end

  def requires_multiple_payments?
    general_balance_due.positive? && sponsors_balance_due.positive?
  end

  def payment_due_date
    if manual_payment.due_date
      manual_payment.due_date.strftime("%B %e, %Y")
    else
      "--"
    end
  end
end
