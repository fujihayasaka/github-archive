# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Transfers::ListComponent < ApplicationComponent
  sig do
    params(
      sponsorable_login: String,
      stripe_account: Billing::StripeConnect::Account,
      page: Integer,
      limit: Integer,
      starting_after: T.nilable(String),
      ending_before: T.nilable(String),
      paginate: T::Boolean,
      sponsor: T.nilable(String)
    ).void
  end
  def initialize(
    sponsorable_login:,
    stripe_account:,
    page:,
    limit: ::Billing::Stripe::Transfer::LIMIT,
    starting_after: nil,
    ending_before: nil,
    paginate: true,
    sponsor: nil
  )
    @sponsorable_login = sponsorable_login
    @stripe_account = stripe_account
    @page           = page
    @limit          = limit
    @starting_after = starting_after
    @ending_before  = ending_before
    @paginate       = T.let(fetch_or_fallback([true, false], paginate, true), T::Boolean)
    @stripe_error   = T.let(nil, T.nilable(String))
    @sponsor        = sponsor
  end

  private

  sig { returns String }
  attr_reader :sponsorable_login

  sig { returns Billing::StripeConnect::Account }
  attr_reader :stripe_account

  sig { returns Integer }
  attr_reader :page

  sig { returns Integer }
  attr_reader :limit

  sig { returns T.nilable(String) }
  attr_reader :starting_after

  sig { returns T.nilable(String) }
  attr_reader :ending_before

  sig { returns T::Boolean }
  attr_reader :paginate

  sig { returns T.nilable(String) }
  attr_reader :sponsor

  sig { returns T::Boolean }
  def render?
    sponsorable_login.present?
  end

  sig { returns T.nilable(String) }
  def stripe_error
    transfers # load the transfers to trigger the error, if any
    @stripe_error
  end

  sig { returns T::Array[Billing::Stripe::Transfer] }
  memoize def transfers
    stripe_account.stripe_transfers(
      starting_after,
      ending_before,
      limit: limit,
      sponsor: sponsor,
    )
  rescue Stripe::InvalidRequestError => err
    @stripe_error = "Could not get transfers: #{err}"
    []
  end

  sig { returns T::Array[Billing::BillingTransaction] }
  memoize def billing_transactions
    ::Billing::BillingTransaction.for_zuora_transaction_id(transfers.map(&:transfer_group)).to_a
  end

  sig { params(transfer: Billing::Stripe::Transfer).returns(T.nilable(Billing::BillingTransaction)) }
  def billing_transaction_for(transfer)
    billing_transactions.detect { |t| t.platform_transaction_id == transfer.transfer_group }
  end

  sig { returns(T::Boolean) }
  memoize def show_match_column?
    transfers.any? { |transfer| transfer.match_amount.positive? || transfer.match_amount_reversed.positive? }
  end

  sig { returns(T::Boolean) }
  memoize def show_amount_flags_column?
    transfers.any? do |transfer|
      transfer.fully_reversed? || transfer.partially_reversed? || transfer.charged_back?
    end
  end

  sig { returns Integer }
  def previous_page
    previous = page - 1
    [1, previous].max
  end

  sig { returns Integer }
  def next_page
    page + 1
  end

  sig { returns T::Boolean }
  def empty_results?
    transfers.count.zero?
  end

  sig { returns T::Boolean }
  def first_page?
    page == 1
  end

  sig { returns T::Boolean }
  def has_next_page?
    transfers.count == limit
  end

  sig { returns T::Boolean }
  def has_previous_page?
    !first_page?
  end

  sig { returns String }
  def displayed_count
    has_next_page? ? "#{transfers.count}+" : "#{transfers.count}"
  end

  sig { returns T.nilable(String) }
  def next_page_url
    return unless has_next_page?

    transfer = transfers.last
    return unless transfer

    stafftools_sponsors_member_stripe_connect_account_transfers_path(
      sponsorable_login,
      stripe_account,
      starting_after: transfer.transfer_id,
      page: next_page
    )
  end

  sig { returns T.nilable(String) }
  def previous_page_url
    return if first_page?

    transfer = transfers.first
    return unless transfer

    stafftools_sponsors_member_stripe_connect_account_transfers_path(
      sponsorable_login,
      stripe_account,
      ending_before: transfer.transfer_id,
      page: previous_page
    )
  end

  sig { returns T::Boolean }
  def show_pagination?
    return false unless paginate
    !empty_results?
  end

  sig { returns T.nilable(Billing::Stripe::Payout) }
  memoize def latest_payout
    response = stripe_account.latest_payout
    response.result if response&.success?
  end

  sig { returns Integer }
  def payment_header_column_span
    total = 1 # Amount column
    total += 1 if show_match_column?
    total += 1 if show_amount_flags_column?
    total
  end
end
