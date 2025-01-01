# typed: true
# frozen_string_literal: true

module Billing
  class ReverseTransactionJob < BillingJob
    discard_on ActiveRecord::RecordNotFound

    locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

    def perform(transaction, skip_email: false)
      with_write { GitHub::Billing.refund_transaction(transaction.transaction_id, skip_email: skip_email) }
    end
  end
end
