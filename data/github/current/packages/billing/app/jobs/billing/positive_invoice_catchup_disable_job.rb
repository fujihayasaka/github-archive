# typed: strict
# frozen_string_literal: true

module Billing
  class PositiveInvoiceCatchupDisableJob < BillingJob
    extend T::Sig

    include GitHub::Billing::ZuoraRateLimitHandler
    queue_as :billing

    ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, PositiveInvoiceCatchupDisableJob)

      zuora_rate_limit_handler(self, error)
    end

    locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

    sig { params(zuora_account_id: String, invoice_amount: T.any(String, Billing::Types::Numeric)).void }
    def perform(zuora_account_id:, invoice_amount:)
      # Could have a general-purpose and a Sponsors-specific plan subscription, but both will be tied to the same
      # account, so just grab either one:
      plan_subscription = ::Billing::PlanSubscription.joins(:customer)
        .merge(Customer.with_zuora_account_id(zuora_account_id)).first
      account = plan_subscription&.billable_entity
      amount  = ::Billing::Money.parse(invoice_amount).cents

      with_write do
        ::Billing::DisableAccountsWithUncollectableInvoices.perform(account: account, amount: amount)
      end
    end
  end
end
