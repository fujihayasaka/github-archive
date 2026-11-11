# typed: true
# frozen_string_literal: true

class Billing::Settings::ManualDunningBannerComponent < ApplicationComponent
  def initialize(account:)
    @account = account
  end

  def pay_now_path
    if account.user?
      bill_pay_new_path
    elsif account.organization?
      org_bill_pay_new_path(organization_id: account.display_login)
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
