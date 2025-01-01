# typed: true
# frozen_string_literal: true

# This job runs on a schedule to ensure any Dependabot Security Updates that have not
# been updated by the Dependabot service after their SLA has expired are marked as
# errored.
class DependabotSecurityUpdateTimeoutCleanupJob < ApplicationJob
  schedule interval: 1.hour
  queue_as :dependabot
  locked_by timeout: 10.minutes, key: ->(job) { job.class.name }
  retry_on_dirty_exit

  # We want to avoid attempting to update an excessive number of rows
  # in each each interval in the event we ever exceed our current
  # steady state for some reason.
  #
  # This ensures that we fail over to 'nibbling' at the table if it
  # ever becomes excessively backlogged.
  MAX_JOB_SLICE = 10_000.freeze

  exempt_from_tenant_context_requirement

  def perform
    @start_time = Time.now
    # We use a sliding window to only cleanup jobs within 1 interval of the timeout period to avoid
    # any issues if the job has to be stopped for a protracted period of time.
    #
    # If there are ever 'stale' jobs outside this window we should prefer to clean them up via a backfill
    @manual_timed_out = @start_time - RepositoryDependencyUpdate::DEPENDABOT_MAX_WAIT_FOR_MANUAL
    @manual_stale = @manual_timed_out - RepositoryDependencyUpdate::DEPENDABOT_MAX_WAIT_FOR_MANUAL
    @automatic_timed_out = @start_time - RepositoryDependencyUpdate::DEPENDABOT_MAX_WAIT
    @automatic_stale = @automatic_timed_out - RepositoryDependencyUpdate::DEPENDABOT_MAX_WAIT

    cleanup_manual_updates
    cleanup_automatic_updates
  end

  private

  def cleanup_manual_updates
    timed_out_manual_updates.find_each(batch_size: 1000) do |dependency_update|
      RepositoryDependencyUpdate.throttle do
        with_write { dependency_update.cleanup_dependabot_time_out! }
      end
    end
  end

  def timed_out_manual_updates
    requested_security_updates.
      where(trigger_type: "manual").
      where("created_at BETWEEN ? AND ?", @manual_stale, @manual_timed_out).
      limit(MAX_JOB_SLICE)
  end

  def cleanup_automatic_updates
    timed_out_automatic_updates.find_each(batch_size: 100) do |dependency_update|
      with_write { dependency_update.cleanup_dependabot_time_out! }
    end
  end

  def timed_out_automatic_updates
    requested_security_updates.
      where.not(trigger_type: "manual").
      where("created_at BETWEEN ? AND ?", @automatic_stale, @automatic_timed_out).
      limit(MAX_JOB_SLICE)
  end

  def requested_security_updates
    RepositoryDependencyUpdate.visible.requested
  end
end
