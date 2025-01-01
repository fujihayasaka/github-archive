# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Transfers::TransferComponent < ApplicationComponent
  extend T::Sig

  # sponsorable_login - the String login of the User or Organization the sponsorship was for
  sig do
    params(
      transfer: Billing::Stripe::Transfer,
      sponsorable_login: String,
      latest_payout: T.nilable(Billing::Stripe::Payout),
      stripe_account: Billing::StripeConnect::Account,
      billing_transaction: T.nilable(Billing::BillingTransaction),
      show_match_column: T::Boolean,
      show_amount_flags_column: T::Boolean
    ).void
  end
  def initialize(transfer:, sponsorable_login:, latest_payout:, stripe_account:, billing_transaction:, show_match_column: true, show_amount_flags_column: true)
    @transfer = transfer
    @sponsorable_login = sponsorable_login
    @latest_payout = latest_payout
    @stripe_account = stripe_account
    @billing_transaction = billing_transaction
    @show_match_column = show_match_column
    @show_amount_flags_column = show_amount_flags_column
  end

  private

  sig { returns(Billing::Stripe::Transfer) }
  attr_reader :transfer

  sig { returns(String) }
  attr_reader :sponsorable_login

  sig { returns(T.nilable(Billing::Stripe::Payout)) }
  attr_reader :latest_payout

  sig { returns(Billing::StripeConnect::Account) }
  attr_reader :stripe_account

  sig { returns(T.nilable(Billing::BillingTransaction)) }
  attr_reader :billing_transaction

  sig { returns(T::Boolean) }
  def show_match_column?
    @show_match_column
  end

  sig { returns(T::Boolean) }
  def show_amount_flags_column?
    @show_amount_flags_column
  end

  sig { returns Integer }
  def total_columns
    total = 7 # Transfer ID, Transaction ID, Amount, Sponsor, Flags, Transferred at, Options
    total += 1 if show_match_column?
    total += 1 if show_amount_flags_column?
    total
  end

  sig { returns(T::Array[Billing::BillingTransaction::LineItem]) }
  memoize def sponsorship_line_items
    transfer.sponsorship_line_items
  end

  sig { returns(T::Array[SponsorsTier]) }
  memoize def sponsors_tiers
    sponsorship_line_items.map(&:subscribable)
  end

  sig { returns(T::Boolean) }
  memoize def possibility_of_reversal_mismatch?
    transfer.possibility_of_reversal_mismatch?
  end

  sig { returns(T::Boolean) }
  def has_been_paid_out?
    transfer.has_been_paid_out?(stripe_account, latest_payout)
  end

  sig { returns String }
  def verify_url
    transfer.transfer_url.presence || transfer.platform_url
  end

  sig { returns(T::Array[T.any(String, Symbol)]) }
  memoize def unique_sponsors_tier_frequencies
    sponsors_tiers.map(&:frequency).uniq
  end

  sig { returns(T.nilable(Symbol)) }
  memoize def frequency
    if unique_sponsors_tier_frequencies.size == 1
      if unique_sponsors_tier_frequencies.first == "one_time"
        :one_time
      else
        :recurring
      end
    elsif unique_sponsors_tier_frequencies.any?
      :mixed
    end
  end

  sig { returns(T::Boolean) }
  def render?
    transfer.present? && sponsorable_login.present?
  end

  sig { params(money_value: Billing::Money).returns(String) }
  def formatted_with_default_currency(money_value)
    "#{money_value.format(no_cents_if_whole: false)} #{money_value.currency.iso_code}"
  end

  sig { params(money_value: Billing::Money, destination_currency: T.nilable(String)).returns(String) }
  def formatted_with_destination_currency(money_value, destination_currency)
    destination_currency ||= "USD"
    destination = money_value.exchange_to(destination_currency)
    "#{destination.format(no_cents_if_whole: false)} #{destination_currency}"
  end

  # If the transfer's destination is also 'USD', we shouldn't gum up the
  # output with the conversion.
  sig { returns(T::Boolean) }
  def show_localized_amount?
    transfer.destination_currency&.upcase != "USD"
  end

  sig { returns T.nilable(String) }
  def transferred_at
    transfer.transferred_at&.strftime("%Y-%m-%d")
  end

  sig { returns(T::Boolean) }
  def show_match_amount?
    transfer.match_amount.positive?
  end

  sig { returns(T::Boolean) }
  def show_match_amount_reversed?
    transfer.match_amount_reversed.positive?
  end

  sig { params(value: String).returns(T.nilable(String)) }
  def truncate_stripe_id(value)
    value.size > 6 ? value[-6..-1] : value
  end
end
