# typed: true
# frozen_string_literal: true

module Billing
  class CheckPayoutsLedgerDiscrepanciesJob < BillingJob
    queue_as :billing
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }

    exempt_from_tenant_context_requirement

    # Public: Checks unresolved discrepancies to see if they have been resolved
    # and sends a gauge metric about unresolved discrepancies
    #
    # Returns nothing
    def perform
      unresolved_discrepancies.each do |discrepancy|
        if discrepancy.ledger_balance.in_balance?
          with_write { discrepancy.update(status: :resolved) }
        else
          with_write { discrepancy.touch }
        end
      end

      GitHub.dogstats.gauge("billing.payouts_ledger.discrepancy_count", unresolved_discrepancies.count)

      if unresolved_discrepancies.any?
        max_age_in_milliseconds = (Time.now.to_i - unresolved_discrepancies.minimum(:created_at).to_i) * 1000
        GitHub.dogstats.gauge("billing.payouts_ledger.discrepancy_max_age", max_age_in_milliseconds)
      end
    end

    private

    def unresolved_discrepancies
      PayoutsLedgerDiscrepancy.unresolved
    end
  end
end
