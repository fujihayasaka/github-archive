# typed: true
# frozen_string_literal: true

class Sponsors::Payouts::PayoutThresholdComponent < ApplicationComponent
  PAYOUT_THRESHOLD_HELP_LINK = "https://stripe.com/docs/payouts#minimum-payout-amounts"

  def initialize(balance:)
    @balance = balance
  end

  delegate :currency, to: :balance

  private

  attr_reader :balance

  def render?
    balance.present? && show_payout_threshold_message?
  end

  def formatted_threshold_amount
    threshold = Billing::Money.new(Billing::StripeConnect::Account.payout_threshold_for(currency.id), currency)
    threshold = Billing::Stripe::Payout.special_case_subunit(threshold, currency.id)
    T.cast(threshold, Billing::Money).format(with_currency: show_currency_suffix?)
  end

  def show_currency_suffix?
    currency.id != :usd && currency.symbol == "$"
  end

  def show_payout_threshold_message?
    balance.cents < Billing::StripeConnect::Account.payout_threshold_for(currency.id)
  end
end
