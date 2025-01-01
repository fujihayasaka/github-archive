# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SuspendPlanSubscriptionJob < BillingJob
  queue_as :zuora

  discard_on ActiveJob::DeserializationError

  RETRYABLE_ERRORS = ::Billing::Zuora::RETRYABLE_ERRORS + [
    GitHub::Restraint::UnableToLock,
  ]

  RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform(plan_subscription)
    with_write do
      plan_subscription.suspend
      result = Billing::Zuora::ZeroOutInvoices.for_subscription(plan_subscription.zuora_subscription_number)
      plan_subscription.update_balance_from_zuora(origin: self.class.name) if result.success?
    end
  end
end
