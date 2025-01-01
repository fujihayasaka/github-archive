# typed: true
# frozen_string_literal: true

# This job cleans up notification summaries
class DeleteExpiredNotificationSummariesJob < TimedJob
  extend T::Helpers

  RESTRAINT_LOCK_KEY = "delete-expired-notification-summaries-lock"
  RESTRAINT_LOCK_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 10.minutes

  EXPIRATION_PERIOD = 3.months
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

  sig do
    override
      .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
      .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
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

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs)
    summary = T.cast(item, NotificationSummary)
    GitHub.dogstats.increment("notifications.summaries.delete_job.processed")

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
    })
  end
end
