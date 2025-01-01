# typed: true
# frozen_string_literal: true

class Sponsors::Payouts::NextPayoutComponent < ApplicationComponent
  # sponsors_listing - a SponsorsListing
  # balance - a Billing::Money instance
  def initialize(sponsors_listing:, balance:)
    @sponsors_listing = sponsors_listing
    @balance = balance
  end

  private

  attr_reader :balance, :sponsors_listing

  def render?
    return false unless sponsors_listing.present? && balance.present?

    # allow unapproved listings to display info about required tax forms
    if sponsors_listing.approved?
      enough_trust_for_payout_info?
    else
      true
    end
  end

  def enough_trust_for_payout_info?
    Sponsors::TrustSystem.enough_trust_for_payout_info?(
      actor: current_user,
      sponsorable: sponsors_listing.sponsorable
    )
  end

  def formatted_money
    currency = balance.currency # Money::Currency instance

    # avoid confusion between USD and other currencies using $ by postfixing
    # their three-letter currency code.
    show_suffix = (currency.id != :usd) && (currency.symbol == "$")

    balance.format(with_currency: show_suffix)
  end

  def tax_form_path
    sponsorable_dashboard_path(sponsors_listing.sponsorable_login, anchor: "tax-form")
  end

  memoize def next_payout_date
    sponsors_listing.next_payout_date
  end

  def next_payout_date_known?
    next_payout_date.present?
  end

  def show_known_next_payout_date?
    # If you're not using a fiscal host, we should show your payout date
    !sponsors_listing.uses_fiscal_host?
  end

  def formatted_next_payout_date
    next_payout_date.strftime("%b %d")
  end

  memoize def on_payout_probation?
    sponsors_listing.on_payout_probation?
  end

  def probation_days
    SponsorsListing::PAYOUT_PROBATION_DAYS
  end

  def help_link
    "#{GitHub.help_url}/articles/managing-your-payouts-from-github-sponsors" \
      "#about-payouts-from-github-sponsors"
  end

  def show_exchange_rate_note?
    balance.currency.id != :usd
  end
end
