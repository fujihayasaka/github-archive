# typed: true
# frozen_string_literal: true

class Billing::Settings::ManualDunningBannerComponent < ApplicationComponent
  def initialize(account:)
    @account = account
  end

  sig { returns(T::Boolean) }
  def eligible_for_rbi_opt_in?
    return false unless account.user?

    BillingSettings::RBIRecurringPaymentsController::ELIGIBLE_USER_IDS.include?(account.id) &&
      account.autopay_disabled_by_india_rbi?
  end

  def pay_now_path
    if account.autopay_disabled_by_india_rbi? &&
        FeatureFlag.vexi.enabled?(:billing_india_rbi_recurring_payments, account, default: false)
      if account.user?
        card_setup_new_path
      elsif account.organization?
        org_card_setup_new_path(organization_id: account.display_login)
      end
    else
      if account.user?
        bill_pay_new_path
      elsif account.organization?
        org_bill_pay_new_path(organization_id: account.display_login)
      end
    end
  end

  private

  attr_reader :account

  def render?
    GitHub.billing_enabled? && account.present? && logged_in? && account.manual_dunning_period.present?
  end

  def formatted_due_date
    account.manual_payment_due_date.strftime("%B %e, %Y")
  end
end
