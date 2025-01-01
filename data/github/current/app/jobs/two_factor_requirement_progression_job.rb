# typed: true
# frozen_string_literal: true

# Job that alters the two_factor_requirement_state of users as they progress from warning to required.
# This job is intended to be run periodically.
# Expects no arguments.
class TwoFactorRequirementProgressionJob < ApplicationJob
  SCHEDULE_INTERVAL = 1.hour
  BATCH_SIZE = 1000
  MAX_THROTTLE_RETRIES = 5

  queue_as :two_factor_requirement_progression
  schedule interval: SCHEDULE_INTERVAL, condition: -> { !GitHub.enterprise? }

  # Don't run more than one of this job at a time
  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on Freno::Error

  def perform
    return unless !GitHub.single_or_multi_tenant_enterprise? && GitHub.flipper[:bulwark_two_factor_requirement_progression].enabled?

    job_start_time = Time.now.utc
    TwoFactorRequirementMetadata.find_for_progression(batch_size: BATCH_SIZE) do |user_ids, new_state|
      GitHub.dogstats.increment("two_factor_requirement_progression_job.batch.count", tags: [
        "new_state:#{User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.key(new_state)}",
      ])

      if GitHub.flipper[:bulwark_two_factor_required_feature].enabled?
        with_write_and_throttle do
          TwoFactorRequirement::Updater.set_2fa_requirement_state(user_ids: user_ids, new_state: new_state)
        end
      end

      return unless GitHub.flipper[:bulwark_two_factor_requirement_progression].enabled?
    end

    time_elapsed = GitHub::Dogstats.duration(job_start_time, Time.now.utc)
    GitHub.dogstats.distribution("two_factor_requirement_progression_job.duration", time_elapsed)
  end

  private

  def with_write_and_throttle
    with_write do
      TwoFactorRequirementMetadata.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        yield
      end
    end
  end
end
