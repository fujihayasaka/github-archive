# typed: true
# frozen_string_literal: true

# This job cleans up notification summaries
class DeleteExpiredNotificationSummariesTier3Job < TimedJob
  extend T::Helpers

  RESTRAINT_LOCK_KEY = "delete-expired-notification-summaries-lock"
  RESTRAINT_LOCK_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 10.minutes

  # this can be changed if we want to introduce more tiers. We add this to
  # logging although it's a constant to be able to reason about this better in
  # logs even if we change periods
  EXPIRATION_PERIOD_START = 12.months
  BATCH_SIZE = 100

  schedule interval: 12.hours
  queue_as :notifications_maintenance
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 10

  # This job iterates over expired values without using a single tenant
  exempt_from_tenant_context_requirement

  around_perform do |_job, block|
    # skip the job if the feature fla is disabled
    unless FeatureFlag.vexi.enabled?("notifications_summaries_tiered_cleanup_tier3", default: false)
      GitHub.logger.info({
        "code.namespace" => self.class.name,
        "gh.delete_expired_notification_summaries_job.disabled" => true,
        "gh.delete_expired_notification_summaries_job.tier" => 3,
        "gh.delete_expired_notification_summaries_job.period_start.months" => EXPIRATION_PERIOD_START.in_months,
        "gh.delete_expired_notification_summaries_job.period_end.months" => "unlimited",
      })
      next
    end
    GitHub::Restraint.new.lock!(RESTRAINT_LOCK_KEY, RESTRAINT_LOCK_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  sig do
    override
      .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
      .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
    with_read do
      NotificationSummary.throttle do
        NotificationSummary
          .where("updated_at < ?", EXPIRATION_PERIOD_START.ago)
          .where("id > ?", offset_id)
          .limit(BATCH_SIZE)
          .select(:id, :list_id, :list_type, :thread_key)
      end
    end
  end

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs)
    summary = T.cast(item, NotificationSummary)
    GitHub.dogstats.increment("notifications.summaries.delete_job.processed", tags: [
     "tier:3",
    ])

    referenced = with_read do
      Newsies::NotificationEntry.throttle do
        Newsies::NotificationEntry
          .for_thread(item.newsies_thread)
          .distinct
          .pluck(:summary_id)
      end
    end
    return if referenced.include?(summary.id)

    saved = with_read do
      Newsies::SavedNotificationEntry.throttle do
        Newsies::SavedNotificationEntry
          .for_list(item.newsies_list)
          .for_thread(item.newsies_thread)
          .distinct
          .pluck(:summary_id)
      end
    end
    return if saved.include?(summary.id)

    GitHub.dogstats.increment("notifications.summaries.delete_job.deleted", tags: [
      "reason:expired",
      "tier:3",
    ])

    with_write do
      summary.delete
    end
  end

  sig { override.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
  def post_process(*args, is_last_job:, num_processed_items:, **kwargs)
    GitHub.logger.info({
      "code.namespace" => self.class.name,
      "gh.delete_expired_notification_summaries_job.is_last_job" => is_last_job,
      "gh.delete_expired_notification_summaries_job.num_processed_items" => num_processed_items,
      "gh.delete_expired_notification_summaries_job.tier" => 3,
      "gh.delete_expired_notification_summaries_job.period_start.months" => EXPIRATION_PERIOD_START.in_months,
      "gh.delete_expired_notification_summaries_job.period_end.months" => "unlimited",
    })
  end
end
