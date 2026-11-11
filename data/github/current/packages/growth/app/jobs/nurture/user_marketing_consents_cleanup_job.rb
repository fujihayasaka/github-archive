# typed: true
# frozen_string_literal: true

module Nurture
  class UserMarketingConsentsCleanupJob < ApplicationJob
    schedule interval: 8.hours
    queue_as :nurture_campaign_sync

    retry_on_dirty_exit

    BATCH_SIZE = 10000
    MAX_BATCHES = 100
    DAYS_OF_DATA_TO_KEEP = 120.days
    JOB_TIMEOUT_SECONDS = 300        # 5 minutes
    TIMEOUT_BUFFER_SECONDS = 30      # 30 seconds

    # Public - scheduled job to remove old user marketing consents
    # We send new user marketing emails to people who have signed up in the last 30 days, so it's unnecessary to keep user data older than that.
    # In case we change our new user strategy, we're keeping the last 120 days of data.
    def perform
      return unless self.class.job_ff_enabled?

      start_time = Time.now
      batch = 0

      loop do
        elapsed = Time.now - start_time
        if elapsed > (JOB_TIMEOUT_SECONDS - TIMEOUT_BUFFER_SECONDS)
          GitHub.logger.info(
            "info.message" => "UserMarketingConsentsCleanupJob stopping early: approaching time limit.",
            "elapsed_seconds" => elapsed,
            "batches_processed" => batch
          )
          break
        end

        rows_to_delete = self.class.rows_to_be_deleted.limit(BATCH_SIZE)
        break unless rows_to_delete.exists?

        with_write do
          rows_to_delete.delete_all
        end

        batch += 1
        break if batch >= MAX_BATCHES
      end

      GitHub.logger.info(
        "info.message" => "Completed cleanup of old user marketing consents. Processed #{batch} batches. #{self.class.rows_to_be_deleted.count} rows of cleanup remain.",
        )
    end

    def self.rows_to_be_deleted
      UserMarketingConsent.where(["created_at < ?", DAYS_OF_DATA_TO_KEEP.ago])
    end

    sig { returns(T::Boolean) }
    def self.job_ff_enabled?
      return true if FeatureFlag.vexi.enabled?(:run_user_marketing_consent_cleanup_job, default: false)

      GitHub.logger.info(
        "info.message" => "run_user_marketing_consent_cleanup_job FF is disabled.  Skipping job.",
      )

      GitHub.dogstats.increment("nurture_campaign.user_marketing_consents_cleanup_job.skipped", tags: ["skipped:ff_disabled"])

      false
    end
  end
end
