# typed: true
# frozen_string_literal: true

# Schedules maintenance jobs for individual gists. See Gist::Maintenance for
# scheduling logic and different types of maintenance tasks.
class GistMaintenanceSchedulerJob < ApplicationJob
  # The queue the scheduler runs on. The actual maintenance jobs don't run on
  # this queue, they're enqueued on the fs maintenance queues.

  queue_as :gist_maintenance_scheduler

  # This job is scheduled in GHE and github.com environments.
  schedule interval: 2.minutes

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  # The number of maintenance jobs to enqueue at each interval.
  JOBS_PER_INTERVAL = 1000

  # Minimum length of time between maintenance runs for any single gist in
  # seconds. Gists that have received maintenance within this time period will
  # not be scheduled unless they've received more than 50 pushes.
  MIN_AGE = 1.week

  def self.enabled?
    !GitHub.multi_tenant_enterprise?
  end

  # Schedules JOBS_PER_INTERVAL maintenance jobs to run and sends histogram
  # stats and maintenance counts to Datadog.
  #
  # Returns Array of gists scheduled for maintenance.
  def perform
    SlowQueryLogger.disabled do
      gists = with_write do
        Gist.schedule_maintenance(JOBS_PER_INTERVAL, MIN_AGE)
      end

      unless gists.empty?
        update_lag_time_histogram(gists)
        update_most_active_histogram(gists)
      end

      Gist.maintenance_counts.each do |status, gist_count|
        GitHub.dogstats.gauge("git_maintenance.count", gist_count, tags: ["type:gist", "status:#{status}"])
        GitHub.stats.gauge("git_maintenance.gist.count.#{status}", gist_count) if GitHub.enterprise?
      end

      gists
    end
  end

  private

  def update_lag_time_histogram(gists)
    most_stale = gists.min_by { |gist| gist.last_maintenance_at || gist.created_at }
    lag_time = Time.now - (most_stale.last_maintenance_at || most_stale.created_at)
    GitHub.dogstats.histogram("gist", lag_time, tags: ["action:maint", "type:lag"])
  end

  def update_most_active_histogram(gists)
    most_active = gists.max_by { |gist| gist.pushed_count_since_maintenance }
    GitHub.dogstats.histogram("gist", most_active.pushed_count_since_maintenance, tags: ["action:maint", "type:most_active"])
  end
end
