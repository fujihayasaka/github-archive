# typed: true
# frozen_string_literal: true

module Billing
  # Represents a single entry in the Payouts Ledger
  #
  # WARNING:
  # Avoid using this class directly for writing to the ledger. Instead, use the
  # Billing::PayoutsLedgerTransaction class to ensure data consistency.
  #
  # Example:
  #
  #   transaction = Billing::PayoutsLedgerTransaction.new(stripe_account)
  #   transaction.add_entry(
  #     transaction_type: :payment,
  #     amount_in_subunits: -10_00,
  #     currency_code: "USD",
  #   )
  #   transaction.add_entry(
  #     transaction_type: :transfer,
  #     amount_in_subunits: 10_00,
  #     currency_code: "USD",
  #   )
  #   transaction.save!
  #
  # WARNING:
  # Avoid unscoped queries of the ledger. All queries should be scoped by
  # Stripe Connect account.
  #
  # Example:
  #
  #   stripe_account = Billing::StripeConnect::Account.find(id)
  #   stripe_account.ledger_entries.where(*criteria)
  class PayoutsLedgerEntry < ApplicationRecord::Domain::Billing
    extend T::Sig

    self.table_name = "billing_payouts_ledger_entries"

    belongs_to :stripe_connect_account, class_name: "Billing::StripeConnect::Account", inverse_of: :ledger_entries
    belongs_to :sponsors_listing
    has_one :sponsorable, through: :sponsors_listing, disable_joins: true
    has_one :sponsors_listing_stafftools_metadata, through: :sponsors_listing, source: :stafftools_metadata
    belongs_to :billing_transaction, class_name: "Billing::BillingTransaction"

    before_validation :set_sponsors_listing_id
    validate :sponsors_listing_is_connected_to_stripe_account
    validate :sponsors_listing_exists, on: :create

    # Transaction types SHOULD correspond to the Stripe webhook kinds in the
    # `Billing::StripeWebhook` model to avoid confusion.
    #
    # See https://github.com/github/gitcoin/blob/ddc5fc56b8fcd33abc21df71888c3e6b174c3611/docs/technical/architecture/payouts_ledger.md#types-of-transactions
    #
    # 10..19 - Cash-flow transactions
    #            These are any transactions where GitHub collects funds from or
    #            returns funds to a cardholder
    # 20..29 - Adjustments to transfers
    #            These are adjustments made prior to transferring funds to a
    #            maintainer, such as matching and fee recovery
    # 30..39 - Transfers
    #            These are the transfer of funds from GitHub's balance to a
    #            maintainer's balance in Stripe
    # 40..49 - Payouts
    #            These are the disbursement of funds from a maintainer's
    #            Stripe balance to their external account
    enum :transaction_type, {
      # Cash-flow transactions
      payment: 10,
      refund: 11,
      chargeback: 12,
      chargeback_reversal: 13,
      # 14 is used by charge_dispute_closed in Billing::StripeWebhook
      invoice_credit: 15,

      # Adjustments to transfers
      github_match: 20,
      github_match_reversal: 21,

      # Transfers
      transfer: 30,           # transfer from GitHub to a maintainer's Stripe account
      transfer_reversal: 31,  # reverses a transfer record because funds were reversed in Stripe
      transfers_paid: 32,     # the companion of a payout entry type in this double-entry ledger system
      # Manual Transfer is meant to be used exactly like the 'transfer' type but exists just to make the
      # distinction between a "regular" transfer and a manual one; used to record missing match amounts;
      # see https://github.com/github/sponsors/blob/ca4b5e534ed87e9003e1cfc4c3c9d481b7dd87aa/docs/operations-playbook/stripe/transfers.md#record-matching-that-has-already-been-paid
      manual_transfer: 33,
      inter_account_transfer: 34, # companion to transfer_reversal entries that indicate a request to move funds
      # between a listing's Stripe Connect accounts.

      # Payouts
      payout: 40,
      payout_failure: 41,
    }

    # Public: Filter ledger entries to those that have a primary reference ID set at all, or to
    # those with a particular primary reference ID. We store Stripe transfer IDs in this field.
    #
    # primary_reference_id - optional String ID to filter by; defaults to including all ledger
    #                        entries that have a non-null value for this field
    scope :with_primary_reference_id, ->(primary_reference_id = nil) do
      if primary_reference_id
        where(primary_reference_id: primary_reference_id)
      else
        where.not(primary_reference_id: nil)
      end
    end

    scope :net_sponsors_matches, -> do
      where(transaction_type: [:github_match, :github_match_reversal])
    end

    scope :net_transfers, -> do
      where(transaction_type: [:transfer, :transfer_reversal, :manual_transfer])
    end

    scope :net_transfers_or_no_transaction_type, -> do
      net_transfers.or(where(transaction_type: nil))
    end

    scope :net_transfers_with_matches, -> { net_sponsors_matches.or(net_transfers) }
    scope :has_sponsors_listing, -> { where.not(sponsors_listing_id: nil) }
    scope :sponsors_listing_transfers, -> { net_transfers.has_sponsors_listing }
    scope :for_sponsors_listing, ->(listing) { where(sponsors_listing_id: listing) }
    scope :has_billing_transaction, -> { where.not(billing_transaction_id: nil) }

    scope :for_stripe_account, ->(stripe_account) do
      where(stripe_connect_account_id: stripe_account)
    end

    scope :payments_for_charge_id, ->(charge_id) do
      payment.where(stripe_charge_id: charge_id)
    end

    # Public: Filter ledger entries to just those for the specified listing and that occurred
    # on or after the specified time. If no time is given, all ledger entries for the specified
    # listing will be returned.
    scope :for_sponsors_listing_and_since, ->(listing, timestamp) do
      if timestamp
        for_sponsors_listing(listing).in_date_range(timestamp..)
      else
        for_sponsors_listing(listing)
      end
    end

    # Public: Get ledger entries for Sponsors listings that were created on or after the listing's
    # last payout was made in Stripe. If no payout has been recorded for a listing, all its ledger
    # entries will be included.
    scope :since_last_sponsors_payout, -> do
      listing_ids = has_sponsors_listing.pluck(:sponsors_listing_id).uniq
      last_payout_times_by_listing_id = SponsorsListing.where(id: listing_ids)
        .pluck(:id, :last_payout_at)

      if last_payout_times_by_listing_id.empty?
        has_sponsors_listing
      else
        sponsors_listing_id, last_payout_at = last_payout_times_by_listing_id.first
        ledger_entries = for_sponsors_listing_and_since(sponsors_listing_id, last_payout_at)

        last_payout_times_by_listing_id.drop(1).each do |(sponsors_listing_id, last_payout_at)|
          ledger_entries = ledger_entries.or(
            for_sponsors_listing_and_since(sponsors_listing_id, last_payout_at)
          )
        end

        ledger_entries
      end
    end

    scope :in_date_range, ->(date_range) { where(transaction_timestamp: date_range) }

    scope :since, ->(time) { in_date_range(time...) }

    scope :most_recent_transaction_timestamp_first, -> { order(transaction_timestamp: :desc) }

    # Public: Get a monetary representation of this ledger entry.
    #
    # absolute - whether to return the absolute value of the entry amount or not
    #
    # Returns a Billing::Money.
    def to_money(absolute: false)
      amount = absolute ? amount_in_subunits.abs : amount_in_subunits
      ::Billing::Money.new(amount, currency_code)
    end

    # Public: Filter SponsorsListing IDs depending on how each listing's sum of transfers compares(using raw_operator) with
    # the value of the amount parameter.
    #
    # sponsors_listing_ids - Array of SponsorsListing IDs
    # raw_operator         - Symbol for operation
    # amount               - Integer the sum of the transfer will be compared with
    #
    # Returns array of SponsorsListing IDs or an empty array
    def self.sponsors_listing_ids_with_transfer_sum(sponsors_listing_ids, raw_operator = :gteq, amount = 0)
      operator = case raw_operator.to_sym
      when :gteq then ">="
      when :gt then ">"
      when :lteq then "<="
      when :lt then "<"
      else
        "="
      end

      Billing::PayoutsLedgerEntry.sponsors_listing_transfers
        .where(sponsors_listing_id: sponsors_listing_ids)
        .group(:sponsors_listing_id)
        .having("SUM(amount_in_subunits) #{operator} ?", amount)
        .pluck(:sponsors_listing_id)
    end

    # Public: The Stripe account id (e.g. "acct_FOO") for this ledger entry
    def stripe_account_id
      stripe_connect_account&.stripe_account_id
    end

    sig { returns T.nilable(Integer) }
    def billing_transaction_user_id
      billing_transaction&.user_id
    end

    def instrument_early_fraud_warning(early_fraud_warning_event)
      # fraud warnings can only be emitted against payments, as the chargeback tracks to the
      # payment and is unrelated to any transfers or payouts, etc.
      return unless payment?

      # Emits a Hydro event
      GlobalInstrumenter.instrument("sponsors.early_fraud_warning",
        stripe_fraud_id: early_fraud_warning_event[:stripe_fraud_id],
        actionable: early_fraud_warning_event[:actionable],
        stripe_charge_id: early_fraud_warning_event[:stripe_charge_id],
        fraud_type: early_fraud_warning_event[:fraud_type],
        stripe_timestamp: early_fraud_warning_event[:stripe_timestamp],
        stripe_account_id: stripe_account_id,
        stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing,
        sponsorable: sponsorable,
        sponsors_listing_stafftool_metadata: sponsors_listing_stafftools_metadata,
        sponsor: User.find_by(id: early_fraud_warning_event[:user_id]),
      )
    end

    sig { returns T.nilable(Integer) }
    def sponsorable_id
      sponsors_listing&.sponsorable_id
    end

    private

    def set_sponsors_listing_id
      return if sponsors_listing_id.present?
      self.sponsors_listing_id = stripe_connect_account&.sponsors_listing_id
    end

    def sponsors_listing_is_connected_to_stripe_account
      return unless sponsors_listing && stripe_connect_account_id

      listing = T.must(sponsors_listing)
      allowed_stripe_ids = listing.stripe_connect_account_ids_for_self_or_fiscal_host

      unless allowed_stripe_ids.include?(stripe_connect_account_id)
        errors.add(:stripe_connect_account, "is not associated with " \
          "#{listing.sponsorable_login}'s Sponsors profile")
      end
    end

    def sponsors_listing_exists
      return if sponsors_listing
      errors.add(:sponsors_listing_id, "must exist")
    end
  end
end
