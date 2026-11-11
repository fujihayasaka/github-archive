# typed: true
# frozen_string_literal: true

class Billing::Settings::Payments::SummaryComponent < ApplicationComponent
  sig { params(manual_payment: Billing::ManualPayment).void }
  def initialize(manual_payment:)
    @manual_payment = manual_payment
  end

  private

  attr_reader :manual_payment

  delegate :purpose, :target, :balance_due, to: :manual_payment

  def render?
    GitHub.billing_enabled?
  end

  def bill_pay_href(purpose:)
    if target.autopay_disabled_by_india_rbi? &&
        FeatureFlag.vexi.enabled?(:billing_india_rbi_recurring_payments, target, default: false)
      return card_setup_href(purpose: purpose)
    end

    if target.user?
      bill_pay_new_path(purpose: purpose)
    elsif target.business?
      billing_settings_one_time_payment_enterprise_path(target, purpose: purpose)
    else
      org_bill_pay_new_path(organization_id: target, purpose: purpose)
    end
  end

  def card_setup_href(purpose:)
    if target.user?
      card_setup_new_path(purpose: purpose)
    elsif target.business?
      billing_settings_card_setup_enterprise_path(target, purpose: purpose)
    else
      org_card_setup_new_path(organization_id: target, purpose: purpose)
    end
  end

  def show_ghas_warning?
    return false unless target.business?
    return false unless target.trial?
    target.autopay_disabled_by_india_rbi?
  end

  def product_name
    manual_payment.invoice_product&.name
  end
end
