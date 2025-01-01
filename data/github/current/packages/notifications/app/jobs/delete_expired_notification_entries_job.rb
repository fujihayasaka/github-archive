# typed: true
# frozen_string_literal: true

# This job cleans up notification entries
class DeleteExpiredNotificationEntriesJob < TimedJob
  extend T::Helpers

  RESTRAINT_LOCK_KEY = "delete-expired-notification-entries-lock"
  RESTRAINT_LOCK_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 10.minutes

  EXPIRATION_PERIOD = 5.months
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
    unless GitHub.flipper[:notifications_entries_run_cleanup_job].enabled?
      GitHub.logger.info({
        "code.namespace" => self.class.name,
        "gh.delete_expired_notification_entries_job.disabled" => true,
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
      Newsies::NotificationEntry.throttle do
        Newsies::NotificationEntry
          .where("updated_at < ?", EXPIRATION_PERIOD.ago)
          .where("id > ?", offset_id)
          .limit(BATCH_SIZE)
          .select(:id)
      end
    end
  end

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs)
    entry = T.cast(item, Newsies::NotificationEntry)
    GitHub.dogstats.increment("notifications.entries.delete_job.deleted", tags: [
      "reason:expired",
    ])

    with_write do
      Newsies::NotificationEntry.throttle do
        entry.delete
      end
    end
  end

  sig { override.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
  def post_process(*args, is_last_job:, num_processed_items:, **kwargs)
    GitHub.logger.info({
      "code.namespace" => self.class.name,
      "gh.delete_expired_notification_entries_job.is_last_job" => is_last_job,
      "gh.delete_expired_notification_entries_job.num_processed_items" => num_processed_items,
    })
  end
end
