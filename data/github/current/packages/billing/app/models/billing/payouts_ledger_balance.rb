# typed: true
# frozen_string_literal: true

module Billing
  # Class responsible for determining if the ledger for a given Stripe Connect
  # account is in balance
  class PayoutsLedgerBalance
    OutOfBalanceError = Class.new(RuntimeError)

    attr_reader :stripe_account

    # Initialize the PayoutsLedgerBalance
    #
    # stripe_account - The Billing::StripeConnect::Account to query by
    def initialize(stripe_account)
      @stripe_account = stripe_account
    end

    # Public: Creates a PayoutsLedgerDiscrepancy record if a Stripe Connect
    # account's ledger is out of balance
    #
    # This will result in an alert as well as provide a way to trace the alert
    # back to the affected Stripe Connect account
    #
    # Returns Boolean whether or not the ledger is in balance
    def ensure_in_balance
      report unless in_balance?
      in_balance?
    end

    # Public: Creates a PayoutsLedgerDiscrepancy record if a Stripe Connect
    # account's ledger is out of balance
    #
    # Like #ensure_in_balance, but raises OutOfBalanceError as well
    #
    # Returns nothing
    # Raises Billing::PayoutsLedgerBalance::OutOfBalanceError
    def ensure_in_balance!
      raise OutOfBalanceError.new(error_message) unless ensure_in_balance
    end

    # Public: Whether or not the Stripe Connect account's ledger is in balance
    #
    # Each transaction in the ledger will increase or decrease the ledger balance
    # for a particular Stripe Connect account. When the ledger is in balance,
    # these increases and decreases should offset each other and net to zero.
    #
    # While the ledger balance may be non-zero in the middle of operations which
    # affect the balance (e.g. while waiting for a transfer to complete after
    # receiving a payment), the balance should generally be zero, and the ledger
    # should generally not be written to if it is out of balance.
    #
    # See https://github.com/github/gitcoin/blob/main/docs/technical/architecture/payouts_ledger.md
    # for more information.
    #
    # Returns Boolean
    def in_balance?
      balance.zero?
    end

    private

    def balance
      @balance ||= ledger_entries.sum(:amount_in_subunits)
    end

    def ledger_entries
      stripe_account.ledger_entries
    end

    def report
      Billing::PayoutsLedgerDiscrepancy.create!(
        stripe_connect_account: stripe_account,
        discrepancy_in_subunits: balance,
      )
    end

    def error_message
      "The payouts ledger for Stripe Connect account '#{stripe_account.id}' is out of balance"
    end
  end
end
