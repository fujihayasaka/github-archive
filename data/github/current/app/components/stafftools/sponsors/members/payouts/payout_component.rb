# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Payouts::PayoutComponent < ApplicationComponent
  def initialize(payout:, stripe_account:)
    @payout         = payout
    @stripe_account = stripe_account
  end

  private

  attr_reader :payout, :stripe_account

  def render?
    payout.present? && stripe_account.present?
  end

  def amount
    money_value = ::Billing::Money.new(payout.amount, payout.currency)
    "#{money_value.format(no_cents_if_whole: false)} #{money_value.currency.iso_code}"
  end

  def status
    payout.status.capitalize
  end

  def initiated_date
    Time.at(payout.created).utc.strftime("%Y-%m-%d")
  end

  def arrival_date
    Time.at(payout.arrival_date).utc.strftime("%Y-%m-%d")
  end

  def payout_dashboard_url
    "https://dashboard.stripe.com/#{stripe_account.stripe_account_id}/payouts/#{payout.id}"
  end
end
