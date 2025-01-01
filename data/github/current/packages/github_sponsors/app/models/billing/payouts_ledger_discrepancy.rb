# typed: true
# frozen_string_literal: true

module Billing
  # Represents a balance discrepancy in the Payouts Ledger for a given
  # Stripe Connect account, meaning that the ledger for that particular
  # account is out of balance
  # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  class PayoutsLedgerDiscrepancy < ApplicationRecord::Domain::Billing
    # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
    self.table_name = "billing_payouts_ledger_discrepancies"

    belongs_to :stripe_connect_account, class_name: "Billing::StripeConnect::Account"

    enum :status, {
      unresolved: "unresolved",
      resolved: "resolved",
    }

    # Public: The PayoutsLedgerBalance object for this discrepancy's Stripe
    # Connect account
    #
    # Returns Billing::PayoutsLedgerBalance
    def ledger_balance
      PayoutsLedgerBalance.new(stripe_connect_account)
    end
  end
end
