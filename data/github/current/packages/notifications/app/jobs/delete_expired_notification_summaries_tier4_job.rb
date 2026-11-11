# typed: true
# frozen_string_literal: true

require_relative "delete_expired_notification_summaries_job"

# This job cleans up notification summaries
class DeleteExpiredNotificationSummariesTier4Job < DeleteExpiredNotificationSummariesJob
  queue_as :notifications_maintenance
  retry_on_dirty_exit

  def self.expiration_period_start
    8.months
  end

  def self.expiration_period_end
    10.months
  end

  def self.tier
    4
  end
end
