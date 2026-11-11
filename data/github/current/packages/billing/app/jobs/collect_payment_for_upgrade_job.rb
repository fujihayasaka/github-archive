# typed: strict
# frozen_string_literal: true

class CollectPaymentForUpgradeJob < BillingJob
  queue_as :collect_payment_for_upgrade

  sig { returns(T.nilable(Integer)) }
  attr_reader :user_id

  sig { returns(T.nilable(Integer)) }
  attr_reader :business_id

  sig { returns(T.nilable(JobStatus)) }
  attr_reader :job_status

  sig { returns(T.nilable(::Billing::Types::Account)) }
  attr_reader :billable_entity

  # Catch-all to ensure that we always attempt to update the JobStatus
  # and enqueue the SynchronizePlanSubscriptionJob as a fallback.
  rescue_from(StandardError) do |error|
    T.bind(self, CollectPaymentForUpgradeJob)
    self.skip_synchronous_collection(error) unless error.is_a?(ArgumentError)
    raise error
  end

  # Retry on all common job and synchronization errors with a short delay and limited attempts.
  # The user will be actively waiting for this job to complete so we don't want to wait too long.
  # It's better to fallback to the asynchronous collection if needed.
  RETRYABLE_ERRORS = T.let([
    Aqueduct::Worker::JobKilled,
    *Resiliency::Response::UnavailableExceptions,
    *::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS,
    *::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS,
  ], T::Array[T.class_of(Exception)])
  RETRYABLE_ERRORS.each do |error_class|
    retry_on(error_class, wait: 1.second, attempts: 5) do |job, error|
      job.skip_synchronous_collection(error)
    end
  end

  # Some errors that are normally retryable are considered non-retryable for this job because
  # they are known to take a long time to resolve and we want to avoid blocking the upgrade
  # which would result in a poor user experience.
  NON_RETRYABLE_ERRORS = T.let([
    # Although Zuorest::GatewayTimeoutError is a part of EXTRA_RETRYABLE_ERRORS,
    # we don't want to retry it in this job. This error is raised after hitting
    # Zuora's 2 minute timeout which means the user has already been waiting a
    # very long time. Retrying too soon may also result in duplicate charges due
    # to Zuora still be processing the changes in the background.
    Zuorest::GatewayTimeoutError,
    # DELAYED_RETRYABLE_ERRORS can take a few hours before they're resolved,
    # so it's better to just immediately fallback to asynchronous collection.
    *::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS
  ], T::Array[T.class_of(Exception)])
  NON_RETRYABLE_ERRORS.each do |error_class|
    rescue_from(error_class) do |error|
      T.bind(self, CollectPaymentForUpgradeJob)
      self.skip_synchronous_collection(error)
    end
  end

  # Retry indefinitely on replication errors because the user will
  # be stuck on the waiting page if the JobStatus is not updated.
  # Note: This error can be raised before `perform` is called.
  retry_on(WaitForReplication::DataUnavailable, wait: 5.seconds, attempts: :unlimited)

  sig do
    params(
      user_id: T.nilable(Integer),
      business_id: T.nilable(Integer),
      actor_id: T.nilable(Integer),
      job_status_id: T.nilable(String),
      notify_on_failure: T::Boolean,
      old_plan_name: T.nilable(String),
      old_seat_count: T.nilable(Integer),
      subscription_item_id: T.nilable(Integer),
      old_subscription_item_id: T.nilable(Integer),
      old_subscription_item_quantity: T.nilable(Integer)
    ).void
  end
  def perform(
    user_id: nil,
    business_id: nil,
    actor_id: nil,
    job_status_id: nil,
    notify_on_failure: false,
    old_plan_name: nil,
    old_seat_count: nil,
    subscription_item_id: nil,
    old_subscription_item_id: nil,
    old_subscription_item_quantity: nil
  )
    raise ArgumentError, "Either user_id or business_id must be present" if user_id.nil? && business_id.nil?
    raise ArgumentError, "Both user_id and business_id cannot be present" if user_id.present? && business_id.present?

    # Variables are assigned in order of importance for error handling.
    # This ensures we can always fallback to asynchronous collection if the database is down.
    @user_id = T.let(user_id, T.nilable(Integer))
    @business_id = T.let(business_id, T.nilable(Integer))
    @job_status = T.let(job_status_id ? Billing::JobStatus.find(job_status_id) : nil, T.nilable(JobStatus))
    @billable_entity = T.let(billable_entity_for(user_id: user_id, business_id: business_id), T.nilable(::Billing::Types::Account))

    return unless plan_subscription = billable_entity&.plan_subscription

    if GitHub.zuorest_client
      GitHub.zuorest_client.timeout = 150
      GitHub.zuorest_client.open_timeout = 150
    end

    actor = actor_id ? User.find_by(id: actor_id) : nil
    subscription_item = subscription_item_id ? ::Billing::SubscriptionItem.find_by(id: subscription_item_id) : nil
    old_subscription_item = old_subscription_item_id ? ::Billing::SubscriptionItem.find_by(id: old_subscription_item_id) : nil
    old_plan = old_plan_name ? GitHub::Plan.find(old_plan_name) : nil

    collect_payment_for_upgrade = ::Billing::CollectPaymentForUpgrade.new(plan_subscription,
      old_plan: old_plan, old_seat_count: old_seat_count, actor: actor, subscription_item: subscription_item,
      old_subscription_item: old_subscription_item, old_subscription_item_quantity: old_subscription_item_quantity)

    with_write do
      job_status&.started!
      result = collect_payment_for_upgrade.synchronize
      if result.success?
        job_status&.success!
      else
        collect_payment_for_upgrade.rollback(result.message)
        collect_payment_for_upgrade.send_failure_notification if notify_on_failure
        job_status&.error!(result.message)
      end
    end
  end

  sig { params(error: Exception).void }
  def skip_synchronous_collection(error)
    SynchronizePlanSubscriptionJob.set(wait: 1.hour).perform_later({ user_id: @user_id, business_id: @business_id })
    GitHub.dogstats.increment("collect_payment_for_upgrade_job.skip_synchronous_collection", tags: ["error:#{error.class.name}"])
    GitHub.logger.info(
      error.message,
      "code.namespace" => self.class.name,
      "code.function" => "skip_synchronous_collection",
      "gh.billing.billable_entity.id" => @billable_entity&.id,
      "gh.billing.billable_entity.login" => @billable_entity&.display_login,
      "gh.billing.billable_entity.type" => @billable_entity.class.name,
      "gh.billing.collect_payment_for_upgrade_job.user_id" => @user_id,
      "gh.billing.collect_payment_for_upgrade_job.business_id" => @business_id,
      "gh.billing.collect_payment_for_upgrade_job.job_status_id" => @job_status&.id,
    )

    # Mark the job status as successful since we're falling back to asynchronous collection.
    # This must be the last call in this method in case the database is down.
    with_write { job_status&.success! }
  end

  private

  sig { params(user_id: T.nilable(Integer), business_id: T.nilable(Integer)).returns(T.nilable(::Billing::Types::Account)) }
  def billable_entity_for(user_id: nil, business_id: nil)
    if user_id
      User.find_by(id: user_id)
    elsif business_id
      Business.find_by(id: business_id)
    end
  end
end
