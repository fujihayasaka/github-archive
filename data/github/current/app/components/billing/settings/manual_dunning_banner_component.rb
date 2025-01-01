# typed: true
# frozen_string_literal: true

class Billing::Settings::ManualDunningBannerComponent < ApplicationComponent
  def initialize(account:)
    @account = account
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
