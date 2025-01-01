# typed: true
# frozen_string_literal: true

class ResumePlanSubscriptionJob < BillingJob
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

  locked_by timeout: 5.minutes, key: -> (job) do
    plan_subscription = job.arguments.first

    "#{plan_subscription.class.name}#{plan_subscription.id}"
  end

  def perform(plan_subscription)
    with_write do
      plan_subscription.resume
    end
  end
end
