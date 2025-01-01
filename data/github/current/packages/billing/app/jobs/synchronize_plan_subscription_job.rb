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

  rescue_from(ActiveJob::DeserializationError) do |_error|
    T.bind(self, SynchronizePlanSubscriptionJob)

    business_id = arguments.dig(0, :business_id)
    user_id = arguments.dig(0, :user_id)
    plan_name = arguments.dig(0, :plan_name)
    purpose = arguments.dig(0, :purpose)
    if business_id.present?
      business = Business.find(business_id)
      existing_business = business.present?
      existing_plan_subscription = existing_business && ::Billing::PlanSubscription.exists?(customer_id: business.customer_id)
    else
      existing_user = User.exists?(id: user_id)
      existing_plan_subscription = ::Billing::PlanSubscription.exists?(user_id: user_id)
    end
    GitHub.dogstats.increment("billing.synchronize_plan_subscription.deserialization_error", tags: [
      "user_exists:#{existing_user}",
      "plan_subscription_exists:#{existing_plan_subscription}",
      "purpose:#{purpose}",
    ])

    SynchronizePlanSubscriptionJob.perform_later({
      business_id: business_id, user_id: user_id, plan_name: plan_name, purpose: purpose,
    }, user: nil, business: nil)
  end

  sig { params(options: T::Hash[Symbol, T.untyped], user: T.nilable(User), business: T.nilable(Business)).void }
  def perform(options = {}, user: nil, business: nil)
    options = options.with_indifferent_access
    plan_name = options[:plan_name]
    business_id = options[:business_id]
    user_id = options[:user_id]
    collect = options[:collect]
    purpose = options[:purpose]&.to_sym || Customer::DEFAULT_PURPOSE
    plan_subscription = plan_subscription_for(user_id: user_id, user: user, business_id: business_id,
      business: business, purpose: purpose)
    legacy_status = legacy_tag_value(user_id: user_id, user: user)
    dogstats_tags = [
      "legacy:#{legacy_status}",
      "plan_subscription:#{plan_subscription.present?}",
      "purpose:#{purpose}",
    ]
    Failbot.push("gh.billing.legacy_status" => legacy_status, "gh.billing.synchronization_purpose" => purpose, "gh.user.id" => user_id,
      "gh.plan.name" => plan_name, "gh.job.attempt.count" => exception_executions)

    if GitHub.zuorest_client
      GitHub.zuorest_client.timeout = 120
      GitHub.zuorest_client.open_timeout = 120
    end

    if plan_name && mismatched_plan_names?(plan_subscription, plan_name: plan_name)
      increment_mismatched_plan_names_count(T.must(plan_subscription), plan_name: plan_name, dogstats_tags: dogstats_tags)
    end

    with_write do
      plan_subscription&.synchronize_with_lock(attempts_per_exception: exception_executions, collect: collect)
    end

    dogstats_tags << "success:true"
  rescue => error # rubocop:todo Lint/GenericRescue
    dogstats_tags ||= []
    dogstats_tags += ["success:false", "error_class:#{error.class}"]
    retryable_errors = Resiliency::Response::UnavailableExceptions +
      ::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS +
      ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS +
      ::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS +
      [Aqueduct::Worker::JobKilled, Zuorest::TooManyRequestsError]
    raise if error.class.in?(retryable_errors)
    Failbot.report(error)
  ensure
    increment_legacy_transition_count(dogstats_tags || [])
  end

  private

  sig { params(user_id: T.nilable(Integer), user: T.nilable(User)).returns(T.any(String, T::Boolean)) }
  def legacy_tag_value(user_id:, user:)
    if user
      false
    elsif user_id
      true
    else
      "unknown"
    end
  end

  sig { params(user_id: T.nilable(Integer), user: T.nilable(User), business: T.nilable(Business), business_id: T.nilable(Integer), purpose: Symbol).returns(T.nilable(::Billing::PlanSubscription)) }
  def plan_subscription_for(user_id:, user:, business:, business_id:, purpose:)
    if user
      return user.sponsors_plan_subscription if purpose == :sponsors
      user.plan_subscription
    elsif user_id
      ::Billing::PlanSubscription.where(purpose: purpose).find_by(user_id: user_id)
    elsif business
      if purpose == :sponsors
        business.sponsors_plan_subscription
      else
        business.plan_subscription
      end
    elsif business_id
      business = Business.find(business_id)
      ::Billing::PlanSubscription.where(purpose: purpose).find_by(customer_id: business.customer_id)
    end
  end

  sig { params(dogstats_tags: T::Array[String]).void }
  def increment_legacy_transition_count(dogstats_tags)
    GitHub.dogstats.increment("billing.synchronize_plan_subscription.legacy_transition", tags: dogstats_tags)
  end

  sig { params(plan_subscription: ::Billing::PlanSubscription, plan_name: String, dogstats_tags: T::Array[String]).void }
  def increment_mismatched_plan_names_count(plan_subscription, plan_name:, dogstats_tags:)
    GitHub.dogstats.increment("billing.synchronize_plan_subscription.mismatching_plan_names", tags: [
      "plan_name_arg:#{plan_name}", "user_plan_name:#{plan_subscription.plan_name}"
    ] + dogstats_tags)
  end

  sig { params(plan_subscription: T.nilable(::Billing::PlanSubscription), plan_name: String).returns(T::Boolean) }
  def mismatched_plan_names?(plan_subscription, plan_name:)
    !!(plan_subscription && !plan_subscription.subscribed_to_github_plan?(plan: plan_name))
  end
end
