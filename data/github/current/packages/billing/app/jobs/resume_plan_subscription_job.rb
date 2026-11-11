# typed: strict
# frozen_string_literal: true

class ResumePlanSubscriptionJob < BillingJob
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
    T.bind(self, ResumePlanSubscriptionJob)

    zuora_rate_limit_handler(self, error)
  end

  discard_on ActiveJob::DeserializationError

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

  sig { params(plan_subscription: Billing::PlanSubscription).void }
  def perform(plan_subscription)
    result = with_write { plan_subscription.resume }

    unless result.success?
      GitHub.logger.error(
        "Failed to resume Zuora subscription",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.billing.result.error": result.error_message,
        "gh.billing.plan_subscription.id": plan_subscription.id,
        "gh.billing.zuora.subscription_id": plan_subscription.zuora_subscription_id,
        "gh.billing.zuora.subscription_number": plan_subscription.zuora_subscription_number,
        "gh.billing.zuora.response": result.zuora_result,
      )
    end
  end
end
