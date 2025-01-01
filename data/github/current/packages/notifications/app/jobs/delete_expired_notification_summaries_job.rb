# typed: true
# frozen_string_literal: true

# This job cleans up notification summaries
class DeleteExpiredNotificationSummariesJob < TimedJob
  extend T::Helpers

  RESTRAINT_LOCK_KEY = "delete-expired-notification-summaries-lock"
  RESTRAINT_LOCK_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 10.minutes

  EXPIRATION_PERIOD = 3.months
  EXPIRATION_PERIOD_START = 5.months
  EXPIRATION_PERIOD_END = 7.months
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
    GitHub::Restraint.new.lock!(RESTRAINT_LOCK_KEY, RESTRAINT_LOCK_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  def tiered_enabled?
    FeatureFlag.vexi.enabled?("notifications_summaries_tiered_cleanup_tier1", default: false)
  end

  sig do
    override
      .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
      .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
    if tiered_enabled?
      with_read do
        NotificationSummary.throttle do
          NotificationSummary
            .where(updated_at: (EXPIRATION_PERIOD_END.ago..EXPIRATION_PERIOD_START.ago))
            .where("id > ?", offset_id)
            .limit(BATCH_SIZE)
            .select(:id, :list_id, :list_type, :thread_key)
        end
      end
    else
      with_read do
        NotificationSummary.throttle do
          NotificationSummary
            .where("updated_at < ?", EXPIRATION_PERIOD.ago)
            .where("id > ?", offset_id)
            .limit(BATCH_SIZE)
            .select(:id, :list_id, :list_type, :thread_key)
        end
      end
    end
  end

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs)
    summary = T.cast(item, NotificationSummary)
    GitHub.dogstats.increment("notifications.summaries.delete_job.processed", tags: [
      "tier:1",
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
      "tier:1",
    ])

    with_write do
      summary.delete
    end
  end

  sig { override.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
  def post_process(*args, is_last_job:, num_processed_items:, **kwargs)
    period_start = tiered_enabled? ? EXPIRATION_PERIOD_START : EXPIRATION_PERIOD
    period_end = tiered_enabled? ? EXPIRATION_PERIOD_END : "unlimited"

    GitHub.logger.info({
      "code.namespace" => self.class.name,
      "gh.delete_expired_notification_summaries_job.is_last_job" => is_last_job,
      "gh.delete_expired_notification_summaries_job.num_processed_items" => num_processed_items,
      "gh.delete_expired_notification_summaries_job.tier" => 1,
      "gh.delete_expired_notification_summaries_job.period_start.months" => period_start,
      "gh.delete_expired_notification_summaries_job.period_end.months" => period_end,
    })
  end
end
