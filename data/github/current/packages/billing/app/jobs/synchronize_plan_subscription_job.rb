# typed: strict
# frozen_string_literal: true

class SynchronizePlanSubscriptionJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler

  queue_as :synchronize_plan_subscription

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer, attempts: ::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ATTEMPTS)
  end

  Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer, attempts: ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ATTEMPTS)
  end

  Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: 2.hours, attempts: ::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ATTEMPTS)
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, SynchronizePlanSubscriptionJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(options: T::Hash[Symbol, T.untyped]).void }
  def perform(options = {})
    options = options.with_indifferent_access
    business_id = options[:business_id]
    user_id = options[:user_id]
    collect = options[:collect]
    purpose = options[:purpose]&.to_sym || Customer::DEFAULT_PURPOSE

    raise ArgumentError, "Either user_id or business_id must be present" if user_id.nil? && business_id.nil?
    raise ArgumentError, "Both user_id and business_id cannot be present" if user_id.present? && business_id.present?

    if GitHub.zuorest_client
      GitHub.zuorest_client.timeout = 150
      GitHub.zuorest_client.open_timeout = 150
    end

    if plan_subscription = plan_subscription_for(user_id: user_id, business_id: business_id, purpose: purpose)
      with_write { plan_subscription.synchronize_with_lock(attempts_per_exception: exception_executions, collect: collect) }
    else
      GitHub.logger.warn(
        "No plan subscription found",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.billing.synchronize_plan_subscription_job.business_id": business_id,
        "gh.billing.synchronize_plan_subscription_job.purpose": purpose,
        "gh.billing.synchronize_plan_subscription_job.user_id": user_id,
      )
    end
  end

  private

  sig { params(user_id: T.nilable(Integer), business_id: T.nilable(Integer), purpose: Symbol).returns(T.nilable(::Billing::PlanSubscription)) }
  def plan_subscription_for(user_id:, business_id:, purpose:)
    if user_id
      ::Billing::PlanSubscription.where(purpose: purpose).find_by(user_id: user_id)
    elsif business_id && (business = Business.find_by(id: business_id))
      ::Billing::PlanSubscription.where(purpose: purpose).find_by(customer_id: business.customer_id)
    end
  end
end
