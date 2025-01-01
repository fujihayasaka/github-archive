# typed: true
# frozen_string_literal: true

module Billing
  # Class responsible for writing multiple, balanced entries to the payouts ledger
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
  class PayoutsLedgerTransaction
    include ActiveModel::Validations

    attr_reader :stripe_account, :entries

    validate :entries_in_balance

    # Initialize the PayoutsLedgerTransaction
    #
    # stripe_account - The Billing::StripeConnect::Account for the ledger entries
    def initialize(stripe_account)
      @stripe_account = stripe_account
      @entries = []
    end

    # Add a ledger entry to the transaction
    #
    # attributes - A Hash of attributes that will be used to create the
    #              ledger entry. If stripe_connect_account is specified,
    #              it is ignored in favor of the Stripe Connect account
    #              used for the overall transaction
    #
    # Returns nothing
    def add_entry(attributes)
      ledger_entry = Billing::PayoutsLedgerEntry.new(attributes)
      ledger_entry.stripe_connect_account = stripe_account
      entries << ledger_entry
    end

    # Save all of the ledger entries to the database
    #
    # Returns nothing
    # Raises ActiveModel::ValidationError if the transaction or any ledger entries
    # are invalid
    # Raises Billing::PayoutsLedgerBalance::OutOfBalanceError if the ledger is
    # out of balance prior to saving the transaction
    def save!
      validate!

      Billing::PayoutsLedgerEntry.transaction do
        ensure_ledger_in_balance
        entries.each(&:save!)
      end
    end

    private

    def entries_in_balance
      unless entries.sum(&:amount_in_subunits).zero?
        errors.add(:ledger_entries, "must balance to zero")
      end
    end

    def ensure_ledger_in_balance
      Billing::PayoutsLedgerBalance.new(stripe_account).ensure_in_balance!
    end
  end
end
