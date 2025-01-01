# typed: true
# frozen_string_literal: true

class Sponsors::Payouts::LastPayoutComponent < ApplicationComponent
  def initialize(payout: nil, sponsors_listing:, error: nil, stripe_account: nil, estimated_payout_amount: nil, disable_stripe_links: false)
    @payout = payout
    @sponsors_listing = sponsors_listing
    @error = error
    @stripe_account = stripe_account
    @estimated_payout_amount = estimated_payout_amount
    @disable_stripe_links = disable_stripe_links
  end

  private

  attr_reader :sponsors_listing, :error, :stripe_account, :estimated_payout_amount

  def render?
    sponsors_listing.present?
  end

  def payout?
    @payout.present?
  end

  def payout
    return unless payout?

    # avoid confusion between USD and other currencies using $ by postfixing
    # their three-letter currency code.
    currency = Money::Currency.new(@payout.currency)
    currency_suffix = (currency.id != :usd) && (currency.symbol == "$")
    Billing::Money.new(@payout.amount, @payout.currency).format(with_currency: currency_suffix)
  end

  def payout_pending?
    return false unless payout?

    @payout.status == "pending"
  end

  def payout_failed?
    return false unless payout?

    @payout.status == "failed"
  end

  def failure_message
    if failure_reasons.include?(@payout.failure_code)
      "Your last payout failed because of incorrect bank account details."
    else
      "Your last payout failed."
    end
  end

  def failure_action
    return unless failure_reasons.include?(@payout.failure_code)

    "update your bank information"
  end

  def payout_formatted_created_at
    Time.at(@payout.created)
        .strftime("%b %d")
  end

  def failure_reasons
    Billing::StripeConnect::Account::PAYOUT_FAILURE_REASONS
  end

  def hide_stripe_link?
    @disable_stripe_links || sponsors_listing.uses_fiscal_host?
  end

  def stripe_account_path
    return unless stripe_account
    @stripe_account_path ||= sponsorable_stripe_account_path(sponsors_listing.sponsorable_login, stripe_account)
  end
end
