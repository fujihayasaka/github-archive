# typed: strict
# frozen_string_literal: true

class CloseOutZuoraSubscriptionJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler
  queue_as :zuora

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, CloseOutZuoraSubscriptionJob)

    zuora_rate_limit_handler(self, error)
  end

  sig do
    params(
      zuora_subscription_number: T.nilable(String),
      plan_subscription: T.nilable(::Billing::PlanSubscription),
      collect_payment: T.nilable(T::Boolean)
    ).void
  end
  def perform(zuora_subscription_number:, plan_subscription: nil, collect_payment: false)
    Failbot.push("gh.billing.zuora.subscription_number": zuora_subscription_number)

    # Zuora Subscriptions must be in an Active state in order to be cancelled. Resume the subscription if it is
    # still in a suspended state.
    zuora_subscription = ::Billing::Zuora::Subscription.find(zuora_subscription_number)
    with_write { plan_subscription&.resume } if zuora_subscription&.suspended?

    result = ::Billing::CloseZuoraSubscription.perform(
      zuora_subscription_number: zuora_subscription_number,
      plan_subscription: plan_subscription,
      collect_payment: collect_payment,
    )

    unless result.success?
      zuora_response = result.zuora_result
      GitHub.logger.error(
        "Close out Zuora subscription failed",
        {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.billing.zuora.subscription_number": zuora_subscription_number,
          "gh.billing.plan_subscription.id": plan_subscription&.id,
        }.merge(
          zuora_response.map { |k, v| ["gh.billing.zuora.response.#{k}", v] }.to_h
        )
      )
    end

    # Return nil to ensure that the job result is not depended on. Any calls
    # that need the result should use Billing::CloseZuoraSubscription directly.
    nil
  end
end
