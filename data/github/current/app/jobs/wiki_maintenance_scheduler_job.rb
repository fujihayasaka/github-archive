# typed: true
# frozen_string_literal: true

class WikiMaintenanceSchedulerJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :wiki_maintenance_scheduler

  schedule interval: 10.minutes

  exempt_from_tenant_context_requirement

  # The number of maintenance jobs to enqueue at each interval.
  def jobs_per_interval
    1000
  end

  # Minimum length of time between maintenance runs for any single
  # wiki in seconds. Wikis that have received maintenance
  # within this time period will not be scheduled unless they've received
  # more than 50 pushes.
  def min_age
    1.week
  end

  # Run every interval, schedules jobs_per_interval maintenance jobs to run.
  def perform
    SlowQueryLogger.disabled do
      wikis = RepositoryWiki.schedule_maintenance(jobs_per_interval, min_age)
      return if wikis.empty?

      most_stale = wikis.min_by { |wiki| wiki.last_maintenance_at || wiki.created_at }
      lag_time = Time.now - (most_stale.last_maintenance_at || most_stale.created_at)
      GitHub.dogstats.gauge("wiki.maint.lag", lag_time)

      most_active = wikis.max_by { |wiki| wiki.pushed_count_since_maintenance }
      GitHub.dogstats.gauge("wiki.maint.most-active", most_active.pushed_count_since_maintenance)

      wikis
    end
  end
end
