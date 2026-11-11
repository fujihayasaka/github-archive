# typed: strict
# frozen_string_literal: true

class SuspendPlanSubscriptionJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  queue_as :zuora

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RETRYABLE_ERRORS = T.let(::Billing::Zuora::RETRYABLE_ERRORS + [
    GitHub::Restraint::UnableToLock
  ], T::Array[T.class_of(StandardError)])

  RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, SuspendPlanSubscriptionJob)

    zuora_rate_limit_handler(self, error)
  end

  discard_on ActiveJob::DeserializationError

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

  sig { params(plan_subscription: Billing::PlanSubscription, zero_out_invoices: T::Boolean).void }
  def perform(plan_subscription, zero_out_invoices: false)
    result = with_write { plan_subscription.suspend }

    unless result.success?
      GitHub.logger.error(
        "Failed to suspend Zuora subscription",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.billing.result.error": result.error_message,
        "gh.billing.plan_subscription.id": plan_subscription.id,
        "gh.billing.zuora.subscription_id": plan_subscription.zuora_subscription_id,
        "gh.billing.zuora.subscription_number": plan_subscription.zuora_subscription_number,
        "gh.billing.zuora.response": result.zuora_result,
      )
      return
    end

    if billable_entity = plan_subscription.billable_entity
      invoice_ids = result.zuora_result&.dig("invoiceIds") || [result.zuora_result&.dig("invoiceId")].compact
      invoice_ids.each do |invoice_id|
        Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob.perform_later(
          invoice_id: invoice_id,
          billable_entity: billable_entity,
        )
      end
    end

    if zero_out_invoices
      with_write do
        result = Billing::Zuora::ZeroOutInvoices.for_subscription(plan_subscription.zuora_subscription_number)
        plan_subscription.update_balance_from_zuora(origin: T.must(self.class.name)) if result.success?
      end
    end
  end
end
