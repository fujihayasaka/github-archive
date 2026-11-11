# typed: strict
# frozen_string_literal: true

# This job checks if a user is NOT eligible to receive a nurture campaign email and updates is_eligible_for_nurture_campaign accordingly.

# The eligibility_job will check for eligible users
# The CPM Sync Job will then pick up users with nurture_campaign_eligibility set to true and sync them to CPM.

module Nurture
  class EligibilityAgedOutJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions attempts: 5
    retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 5

    # scheduling is done in timers.fe.rb
    schedule interval: ENV.fetch("ELIGIBILITY_AGED_OUT_JOB_FREQUENCY_SECONDS", "600").to_i # default to 10 min

    queue_as :nurture_campaign_sync

    AGED_OUT_THRESHOLD_DAYS = T.let(ENV.fetch("NURTURE_CAMPAIGN_AGED_OUT_THRESHOLD_DAYS", "14").to_i, Integer)
    LOCK_TTL_SECONDS = T.let(ENV.fetch("ELIGIBILITY_AGED_OUT_JOB_LOCK_TTL_SECONDS", "300").to_i, Integer)

    sig { void }
    def perform
      lock_key = "nurture_campaign_eligibility_aged_out_job_lock"
      concurrent_jobs = 1
      lock_ttl = LOCK_TTL_SECONDS

      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
        GitHub.logger.info(
          "info.message" => "Env vars for EligibilityAgedOutJob",
          "ELIGIBILITY_AGED_OUT_JOB_FREQUENCY_SECONDS" => ENV.fetch("ELIGIBILITY_AGED_OUT_JOB_FREQUENCY_SECONDS", "600").to_i,
        )
        if !self.class.job_ff_enabled?
          GitHub.logger.info(
            "info.message" => "Check if job_ff_enabled? is disabled.",
            "feature_flag" => FeatureFlag.vexi.enabled?(:run_nurture_eligibility_aged_out_job, default: false),
          )
        end
        return unless self.class.job_ff_enabled?

        GitHub.dogstats.time("nurture_campaign.eligibility_aged_out_job") do
          GitHub.dogstats.increment("nurture_campaign.eligibility_aged_out_job.start")

          aged_out_date = AGED_OUT_THRESHOLD_DAYS.days.ago.beginning_of_day

          updated_count = with_write do
            UserMarketingConsent
              .where(marketing_consent: :explicit_optin)
              .where("created_at < ?", aged_out_date)
              .where(is_eligible_for_nurture_campaign: true)
              .update_all(is_eligible_for_nurture_campaign: false, updated_at: Time.current)
          end

          GitHub.dogstats.increment("nurture_campaign.eligibility_aged_out_job.ineligible_users", by: updated_count)

          if updated_count.zero?
            GitHub.logger.info(
              "info.message" => "No ineligible users found",
              "aged_out_date" => aged_out_date
            )
            GitHub.dogstats.increment("nurture_campaign.eligibility_aged_out_job.no_ineligible_users")
          end

          GitHub.logger.info(
            "info.message" => "Finished eligibility aged out job",
          )
          GitHub.dogstats.increment("nurture_campaign.eligibility_aged_out_job.finish")
        end
      end
    end

    sig { returns(T::Boolean) }
    def self.job_ff_enabled?
      return true if FeatureFlag.vexi.enabled?(:run_nurture_eligibility_aged_out_job, default: false)

      GitHub.logger.info(
        "info.message" => "run_nurture_eligibility_aged_out_job FF is disabled.  Skipping job.",
      )

      GitHub.dogstats.increment("nurture_campaign.eligibility_aged_out_job.skipped", tags: ["skipped:ff_disabled"])

      false
    end
  end
end
