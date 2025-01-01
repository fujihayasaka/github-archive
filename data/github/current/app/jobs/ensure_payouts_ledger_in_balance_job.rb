# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EnsurePayoutsLedgerInBalanceJob < ApplicationJob
  queue_as :billing

  # Public: Perform the job
  #
  # stripe_connect_account - The Billing::StripeConnect::Account for which we're
  #                          checking the ledger balance
  #
  # Returns nothing
  def perform(stripe_connect_account)
    with_write do
      Billing::PayoutsLedgerBalance.new(stripe_connect_account).ensure_in_balance
    end
  end
end
