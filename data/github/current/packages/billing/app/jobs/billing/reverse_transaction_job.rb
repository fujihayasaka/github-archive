# typed: strict
# frozen_string_literal: true

module Billing
  class ReverseTransactionJob < BillingJob
    include GitHub::Billing::ZuoraRateLimitHandler

    discard_on ActiveRecord::RecordNotFound

    locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

    ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, UpdateZuoraAccountInformationJob)

      zuora_rate_limit_handler(self, error)
    end

    sig { params(transaction: Billing::BillingTransaction, skip_email: T::Boolean).void }
    def perform(transaction, skip_email: false)
      return unless transaction.refundable?
      with_write { GitHub::Billing.refund_transaction(transaction.transaction_id, skip_email: skip_email) }
    end
  end
end
