# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class BillingUpdateTransactionsWithPendingStatusJob < ApplicationJob
  LOCK_KEY = "billing-transactions-update"

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  queue_as :billing

  retry_on GitHub::Restraint::UnableToLock, wait: 5.minutes do |_job, error|
    T.bind(self, BillingUpdateTransactionsWithPendingStatusJob)

    record_error(error)
  end

  sig { void }
  def perform
    restraint = GitHub::Restraint.new
    restraint.lock!(LOCK_KEY, 1, 1.hour) do
      ::Billing::BillingTransaction.update_transactions_with_pending_status
    end
  end
end
