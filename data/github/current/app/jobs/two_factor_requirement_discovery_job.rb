# typed: true
# frozen_string_literal: true

# Job that discovers users that require two-factor authentication.
# This job is intended to be run periodically.
# Expects no arguments.
class TwoFactorRequirementDiscoveryJob < ApplicationJob
  SCHEDULE_INTERVAL = 1.day
  LOOKBACK_KEY_PREFIX = "#{self}.lookback".freeze
  YIELDED_BATCH_SIZE = 100
  MAX_THROTTLE_RETRIES = 5

  # The first time the job is run, there won't be a lookback stored in KV.
  # Setting this to two weeks to ensure we don't miss any users between running our last transition and enabling this job.
  DEFAULT_LOOKBACK = 2.weeks
  # Extra buffer for lookback to avoid timing issues related to datawarehouse lag.
  LOOKBACK_BUFFER = 10.days

  queue_as :two_factor_requirement_discovery
  schedule interval: SCHEDULE_INTERVAL, condition: -> { !GitHub.enterprise? }

  # Don't run more than one of this job at a time
  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on Freno::Error

  def perform
    return if GitHub.single_or_multi_tenant_enterprise?
    return unless GitHub.flipper[:bulwark_two_factor_requirement_discovery].enabled?

    job_start_time = Time.now.utc
    TwoFactorRequirement::Queries.all.each do |query|
      next unless query.steady_state_enabled?
      lookback = find_lookback(query.reason)
      query.run_query(yielded_batch_size: YIELDED_BATCH_SIZE, lookback: lookback) do |user_ids, requirement_reason|
        GitHub.dogstats.increment("two_factor_requirement_discovery_job.batch.count", tags: [
          "requirement_reason:#{requirement_reason}",
        ])

        if GitHub.flipper[:bulwark_two_factor_required_feature].enabled?
          with_write_and_throttle do
            TwoFactorRequirement::Updater.require_for_reason(user_ids: user_ids, requirement_reason: requirement_reason)
          end
        end
      end
      set_lookback(query.reason, job_start_time)
    end

    time_elapsed = GitHub::Dogstats.duration(job_start_time, Time.now.utc)
    GitHub.dogstats.distribution("two_factor_requirement_discovery_job.duration", time_elapsed)
  end

  private

  def with_write_and_throttle
    with_write do
      TwoFactorRequirementMetadata.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        yield
      end
    end
  end

  def lookback_key(reason)
    "#{LOOKBACK_KEY_PREFIX}.#{reason}"
  end

  # Private: Returns the earliest time that we should look for users that need two-factor authentication.
  # for the given reason.
  #
  # Returns a Time object.
  def find_lookback(reason)
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:2fa_requirement_discovery"])
    lookback = GitHub::Authentication::KV.store.get(lookback_key(reason)).value { nil }
    return DEFAULT_LOOKBACK.ago.utc if lookback.nil?
    Time.at(lookback.to_i)
  end

  # Private: Sets the earliest time that we should look for users that need two-factor authentication.
  # Sets the lookback to the time when the job was run with an extra buffer to avoid timing issues
  # related to datawarehouse lag.
  def set_lookback(reason, time)
    begin
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:2fa_requirement_discovery"])
      with_write { GitHub::Authentication::KV.store.set(lookback_key(reason), (time - LOOKBACK_BUFFER).to_i.to_s) }
    rescue GitHub::KV::UnavailableError
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :two_factor_requirement_discovery_set_lookback, action: :set })
    end
  end
end
