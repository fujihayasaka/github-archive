# typed: true
# frozen_string_literal: true

require_relative "delete_expired_notification_summaries_job"

# This job cleans up notification summaries
class DeleteExpiredNotificationSummariesTier5Job < DeleteExpiredNotificationSummariesJob
  queue_as :notifications_maintenance
  retry_on_dirty_exit

  def self.expiration_period_start
    10.months
  end

  # this is a bit of a hack so we don't need make the base class account for
  # "infinity" for the highest tier job that just deletes everything older
  # than the period start. This isn't actually used in record retrieval (see
  # method override below), but just for logging
  def self.expiration_period_end
    5.years
  end

  def self.tier
    5
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
          .where("updated_at < ?", self.class.expiration_period_start.ago)
          .limit(self.class.batch_size)
          .select(:id, :list_id, :list_type, :thread_key)
      end
    end
  end
end
