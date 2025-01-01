# typed: true
# frozen_string_literal: true

class EnsureRecentlyUpdatedPayoutsLedgersInBalanceJob < ApplicationJob
  exempt_from_tenant_context_requirement

  queue_as :billing

  schedule interval: 4.hours, condition: -> { GitHub.billing_enabled? }

  attr_reader :search_start, :search_end

  # Public: Perform the job
  #
  # cutoff - The amount of time to look back for ledger updates
  #
  # Returns nothing
  def perform(cutoff: 4.hours)
    @search_end = Time.now
    @search_start = search_end - cutoff

    recently_updated_payouts_ledgers.each do |stripe_connect_account|
      EnsurePayoutsLedgerInBalanceJob.perform_later(stripe_connect_account)
    end
  end

  private

  def recently_updated_payouts_ledgers
    Billing::StripeConnect::Account
      .joins(:ledger_entries)
      .where("billing_payouts_ledger_entries.transaction_timestamp BETWEEN ? AND ?", search_start, search_end)
      .distinct
  end
end
