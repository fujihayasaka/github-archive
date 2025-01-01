# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class CollectPaymentForUpgradeJob < BillingJob
  queue_as :collect_payment_for_upgrade
  retry_on_dirty_exit

  sig { returns(T.nilable(::Billing::Types::Account)) }
  attr_reader :billable_entity

  sig { returns(T.nilable(::Billing::CollectPaymentForUpgrade)) }
  attr_reader :collect_payment_for_upgrade

  sig { returns(T.nilable(JobStatus)) }
  attr_reader :job_status

  sig { returns(T.nilable(T::Boolean)) }
  attr_reader :notify_on_failure

  # Catch-all to ensure that we always rollback and set the job status to error.
  rescue_from(StandardError) do |error|
    T.bind(self, CollectPaymentForUpgradeJob)

    self.handle_error_and_rollback(error)
  end

  # Retry all of the common synchronization errors with a short delay and minimal attempts.
  # The user will be actively waiting as we run this job so we don't want to run for too long.
  ::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS.each do |error_class|
    retry_on(error_class, wait: 1.second, attempts: 5) do |job, error|
      job.handle_error_and_rollback(error)
    end
  end

  # Collect payment asynchronously after exhausting the retry attempts for extra retryable errors.
  # These errors can take longer to resolve so we defer the synchronization to the SynchronizePlanSubscriptionJob.
  ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS.each do |error_class|
    retry_on(error_class, wait: 1.second, attempts: 5) do |job, error|
      job.skip_synchronous_collection(error)
    end
  end

  # Collect payment asynchronously for Zuorest::GatewayTimeoutError.
  # While this error is a part of EXTRA_RETRYABLE_ERRORS, we don't want to retry it in this job.
  # This is because this error comes up after hitting Zuora's 120 second timeout limit which means
  # the user has already been waiting for a very long time. In addition, retrying too soon can result
  # in duplicate charges because Zuora may still be processing the changes on their end.
  rescue_from(Zuorest::GatewayTimeoutError) do |error|
    T.bind(self, CollectPaymentForUpgradeJob)

    self.skip_synchronous_collection(error)
  end

  # Collect payment asynchronously when we encounter any delayed retryable errors.
  # These errors may take a few hours to resolve so we defer the synchronization to
  # the SynchronizePlanSubscriptionJob to prevent blocking the upgrade unnecessarily.
  T.unsafe(self).rescue_from(*::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS) do |error|
    T.bind(self, CollectPaymentForUpgradeJob)

    self.skip_synchronous_collection(error)
  end

  # We have no choice but to retry indefinitely for replication errors because we have no way to
  # update the JobStatus which means the user will be stuck on the waiting page forever.
  retry_on(WaitForReplication::DataUnavailable, wait: 3.seconds, attempts: :unlimited)

  sig do
    params(
      billable_entity: ::Billing::Types::Account,
      old_plan_name: String,
      old_seat_count: Integer,
      job_status_id: T.nilable(String),
      notify_on_failure: T::Boolean,
      actor: T.nilable(User),
      subscription_item: T.nilable(::Billing::SubscriptionItem),
      old_subscription_item_quantity: T.nilable(Integer)
    ).void
  end
  def perform(
    billable_entity:,
    old_plan_name:,
    old_seat_count:,
    job_status_id: nil,
    notify_on_failure: false,
    actor: nil,
    subscription_item: nil,
    old_subscription_item_quantity: nil
  )
    return unless billable_entity.plan_subscription.present?
    old_plan = GitHub::Plan.find!(old_plan_name)

    if GitHub.zuorest_client
      GitHub.zuorest_client.timeout = 120
      GitHub.zuorest_client.open_timeout = 120
    end

    @billable_entity = T.let(billable_entity, T.nilable(::Billing::Types::Account))
    @collect_payment_for_upgrade = T.let(::Billing::CollectPaymentForUpgrade.new(billable_entity.plan_subscription, old_plan, old_seat_count, actor, subscription_item, old_subscription_item_quantity),  T.nilable(::Billing::CollectPaymentForUpgrade))
    @job_status = T.let(Billing::JobStatus.find(job_status_id), T.nilable(JobStatus))
    @notify_on_failure = T.let(notify_on_failure, T.nilable(T::Boolean))

    collect_payment_for_upgrade = T.must(@collect_payment_for_upgrade)

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

  sig { params(error: StandardError).void }
  def handle_error_and_rollback(error)
    with_write { collect_payment_for_upgrade&.rollback(error.message) }
    collect_payment_for_upgrade&.send_failure_notification if notify_on_failure
    with_write { job_status&.error!(error.message) }
    Failbot.report(error)
  end

  sig { params(error: StandardError).void }
  def skip_synchronous_collection(error)
    with_write { job_status&.success! }
    if billable_entity.is_a?(Business)
      SynchronizePlanSubscriptionJob.set(wait: 1.hour).perform_later({}, business: billable_entity)
    else
      SynchronizePlanSubscriptionJob.set(wait: 1.hour).perform_later({}, user: billable_entity)
    end
    GitHub.dogstats.increment("collect_payment_for_upgrade_job.skip_synchronous_collection", tags: ["error:#{error.class}"])
    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "skip_synchronous_collection",
      "exception.type" => error.class,
      "exception.message" => error.message,
      "gh.billing.billable_entity.id" => billable_entity&.id,
      "gh.billing.billable_entity.type" => billable_entity.class,
    )
  end
end
