# typed: strict
# frozen_string_literal: true

# This job checks if a user is eligible to receive a nurture campaign email or not, and updates nurture_campaign_eligibility accordingly.
# The CPM Sync Job will then pick up users with nurture_campaign_eligibility set to true and sync them to CPM.

module Nurture
  class EligibilityJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions attempts: 5
    retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 5

    # scheduling is done in timers.fe.rb
    schedule interval: ENV.fetch("ELIGIBILITY_JOB_FREQUENCY_SECONDS", "600").to_i # default to 10 min

    queue_as :nurture_campaign_sync

    AGED_OUT_THRESHOLD_DAYS = T.let(ENV.fetch("NURTURE_CAMPAIGN_AGED_OUT_THRESHOLD_DAYS", "14").to_i, Integer)
    BATCH_SIZE = T.let(ENV.fetch("NURTURE_CAMPAIGN_ELIGIBILITY_JOB_BATCH_SIZE", "1000").to_i, Integer)
    # in a worst case scenario, it can take up to 4 hours for data to be available in CPM, so we don't want to sync users who have just signed up
    # https://microsoft.sharepoint.com/teams/CPMHelp/SitePages/Onboarding-to-CPM.aspx#please-allow-4-hours-to-ensure-consent-updates-are-propagated-across-all-regions
    CPM_DATA_HOLD_SECONDS = T.let(ENV.fetch("NURTURE_CAMPAIGN_CPM_DATA_HOLD_SECONDS", "14400").to_i, Integer) # default to 4 hours
    MAX_RUNTIME_SECONDS = 300
    LOCK_TTL_SECONDS = T.let(ENV.fetch("ELIGIBILITY_JOB_LOCK_TTL_SECONDS", "300").to_i, Integer)

    sig { void }
    def perform
      lock_key = "nurture_campaign_eligibility"
      concurrent_jobs = 1
      lock_ttl = LOCK_TTL_SECONDS

      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
        GitHub.logger.info(
          "info.message" => "Env vars for EligibilityJob",
          "ELIGIBILITY_JOB_FREQUENCY_SECONDS" => ENV.fetch("ELIGIBILITY_JOB_FREQUENCY_SECONDS", "600").to_i,
        )
        if !self.class.job_ff_enabled?
          GitHub.logger.info(
            "info.message" => "Check if job_ff_enabled? is disabled.",
            "feature_flag" => FeatureFlag.vexi.enabled?(:run_nurture_eligibility_job, default: false),
          )
        end
        return unless self.class.job_ff_enabled?

        GitHub.dogstats.time("nurture_campaign.eligibility_job") do
          GitHub.dogstats.increment("nurture_campaign.eligibility_job.start")

          GitHub.logger.info(
            "info.message" => "Starting eligibility job",
          )

          total_updated = 0
          start_time = Time.current
          timeout_threshold = MAX_RUNTIME_SECONDS - 60 # Leave a 60 sec buffer

          oldest_eligible_date = AGED_OUT_THRESHOLD_DAYS.days.ago.beginning_of_day
          newest_eligible_date = CPM_DATA_HOLD_SECONDS.seconds.ago.beginning_of_day
          current_day_start = oldest_eligible_date

          loop do
            current_day_end = current_day_start + 1.day

            GitHub.logger.info(
              "info.message" => "Beginning loop iteration to update eligible users",
            )

            if current_day_start >= newest_eligible_date
              GitHub.logger.info(
                "info.message" => "No more eligible dates to process, exiting loop",
              )
              break
            end
            elapsed = Time.current - start_time
            if elapsed > timeout_threshold
              GitHub.logger.warn(
                "info.message" => "update_eligible_users stopping early: approaching time limit",
                "elapsed_seconds" => elapsed,
                "records_updated" => total_updated
              )
              break
            end

            updated_count = with_write do
              UserMarketingConsent
                .where(marketing_consent: :explicit_optin)
                .where(onboarding_optout_date: nil)
                .where(created_at: current_day_start...current_day_end)
                .update_all(is_eligible_for_nurture_campaign: true, updated_at: Time.current)
            end
            if updated_count.zero?
              GitHub.logger.info(
                "info.message" => "No eligible users found for date range",
                "date_range_start" => current_day_start,
                "date_range_end" => current_day_end
              )
              # increment the day window and move to process the next day
              current_day_start = current_day_end
              next
            else
              total_updated += updated_count
              GitHub.logger.info(
                "info.message" => "Eligible users updated so far: #{total_updated}",
              )
              GitHub.dogstats.increment("nurture_campaign.eligibility_job.eligible_users", by: total_updated)

              GitHub.logger.info(
                "info.message" => "Updated eligible users for date range",
                "date_range_start" => current_day_start,
                "date_range_end" => current_day_end,
                "records_updated" => updated_count
              )
              # increment the day window and move to process the next day
              current_day_start = current_day_end
              next
            end
          end

          GitHub.logger.info(
            "info.message" => "Finished eligibility job",
          )

          GitHub.dogstats.increment("nurture_campaign.eligibility_job.finish")
        end
      end
    end

    sig { returns(T::Boolean) }
    def self.job_ff_enabled?
      return true if FeatureFlag.vexi.enabled?(:run_nurture_eligibility_job, default: false)

      GitHub.logger.info(
        "info.message" => "run_nurture_eligibility_job FF is disabled.  Skipping job.",
      )

      GitHub.dogstats.increment("nurture_campaign.eligibility_job.skipped", tags: ["skipped:ff_disabled"])

      false
    end
  end
end
