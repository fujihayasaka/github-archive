# typed: true
# frozen_string_literal: true

# This job cleans up notification summaries
class DeleteExpiredNotificationSummariesJob < BatchedJob
  extend T::Helpers

  RESTRAINT_LOCK_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 10.minutes

  BATCH_SIZE = 100

  schedule interval: 1.hour
  queue_as :notifications_maintenance
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 5

  # This job iterates over expired values without using a single tenant
  exempt_from_tenant_context_requirement

  sig { returns(Integer) }
  def self.batch_size
    BATCH_SIZE
  end

  sig { returns(Integer) }
  def self.tier
    raise NotImplementedError
  end

  sig { returns(ActiveSupport::Duration) }
  def self.expiration_period_start
    raise NotImplementedError
  end

  sig { returns(ActiveSupport::Duration) }
  def self.expiration_period_end
    raise NotImplementedError
  end

  def self.feature_flag
    "notifications_summaries_tiered_cleanup_tier#{self::tier}"
  end

  around_perform do |job, block|
    # skip the job if the feature flag is disabled
    unless FeatureFlag.vexi.enabled?(job.class.feature_flag, default: false)
      GitHub.logger.info({
        "code.namespace" => self.class.name,
        "gh.delete_expired_notification_summaries_job.disabled" => true,
        "gh.delete_expired_notification_summaries_job.tier" => job.class.tier,
        "gh.delete_expired_notification_summaries_job.period_start.months" => job.class.expiration_period_start.in_months,
        "gh.delete_expired_notification_summaries_job.period_end.months" => job.class.expiration_period_end.in_months,
      })
      next
    end
    GitHub::Restraint.new.lock!("delete-expired-notification-summaries-tier#{job.class.tier}-lock",
                                RESTRAINT_LOCK_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  sig do
    override
      .params(args: T.untyped, timestamp: Time, offset_item_id: Integer,
              progress: Integer, options: T.untyped)
       .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    with_read do
      NotificationSummary.throttle do
        NotificationSummary
          .where(updated_at: (self.class.expiration_period_end.ago..self.class.expiration_period_start.ago))
          .limit(self.class.batch_size)
          .select(:id, :list_id, :list_type, :thread_key)
      end
    end
  end

  sig { override.params(batch: T.untyped, options: T.untyped).returns(T::Boolean) }
  def has_next_batch?(batch, **options)
    # this is a bit of an opportunistic hack to decide whether we want to
    # continue processing another batch. The logic is basically that if we
    # were able to delete anything, we assume there is more. There is an edge
    # case here where we could technically get a batch of summaries that are
    # all referenced and thus stop processing. We'll have to see how often
    # that actually happens in practice.
    (@items_to_delete ||= []).length > 0
  end

  sig { override.params(batch: T.untyped, args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    @items_to_delete = []
    @deleted = 0
    batch.each do |item|
      summary = T.cast(item, NotificationSummary)
      @items_to_delete << summary unless is_referenced?(summary: summary)
    end

    GitHub.dogstats.increment("notifications.summaries.delete_job.to_delete",
                              by: @items_to_delete.length, tags: [
                                "reason:expired",
                                "tier:#{self.class.tier}",
                              ])
    with_write do
      NotificationSummary.throttle do
        @deleted = NotificationSummary.where(id: @items_to_delete).delete_all
        GitHub.dogstats.increment("notifications.summaries.delete_job.deleted",
                                  by: @deleted, tags: [
                                    "reason:expired",
                                    "tier:#{self.class.tier}",
                                  ])
      end
    end
    GitHub.dogstats.increment("notifications.summaries.delete_job.processed",
                              by: batch.length, tags: [
                                "reason:expired",
                                "tier:#{self.class.tier}",
                              ])
    GitHub.logger.info({
      "code.namespace" => self.class.name,
      "gh.delete_expired_notification_summaries_job.num_processed_items" => batch.length,
      "gh.delete_expired_notification_summaries_job.num_deleted_items" => @deleted,
      "gh.delete_expired_notification_summaries_job.tier" => self.class.tier,
      "gh.delete_expired_notification_summaries_job.period_start.months" => self.class.expiration_period_start.in_months,
      "gh.delete_expired_notification_summaries_job.period_end.months" => self.class.expiration_period_end.in_months,
    })
  end

  sig { params(summary: NotificationSummary).returns(T::Boolean) }
  def is_referenced?(summary:)
    referenced = with_read do
      Newsies::NotificationEntry.throttle do
        Newsies::NotificationEntry
          .for_thread(summary.newsies_thread)
          .distinct
          .pluck(:summary_id)
      end
    end
    return true if referenced.include?(summary.id)

    saved = with_read do
      Newsies::SavedNotificationEntry.throttle do
        Newsies::SavedNotificationEntry
          .for_list(summary.newsies_list)
          .for_thread(summary.newsies_thread)
          .distinct
          .pluck(:summary_id)
      end
    end
    return true if saved.include?(summary.id)
    false
  end
end
