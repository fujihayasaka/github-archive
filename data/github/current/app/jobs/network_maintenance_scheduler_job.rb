# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class NetworkMaintenanceSchedulerJob < ApplicationJob
  # Timer that schedules maintenance jobs for individual networks. See
  # RepositoryNetwork::Maintenance for scheduling logic and different types of
  # maintenance tasks.

  queue_as :network_maintenance_scheduler
  retry_on_dirty_exit

  schedule interval: 2.minutes

  exempt_from_tenant_context_requirement

  # The number of maintenance jobs to enqueue at each interval.
  def jobs_per_interval
    if GitHub.enterprise?
      1000
    else
      4000
    end
  end

  # Minimum length of time between maintenance runs for any single
  # network in seconds. Networks that have received maintenance
  # within this time period will not be scheduled unless they've received
  # more than 50 pushes.
  def min_age
    1.week
  end

  # Do not schedule more than this many maintenance jobs on a single host.
  # Once the limit is reached, networks on that host are excluded from scheduling
  # queries.
  def host_threshold
    1000
  end

  # Run every interval, schedules jobs_per_interval maintenance jobs to run.
  def perform
    SlowQueryLogger.disabled do
      networks = with_write { RepositoryNetwork.schedule_maintenance(jobs_per_interval, host_threshold, min_age) }

      unless networks.empty?
        most_stale = networks.min_by { |net| net.last_maintenance_at || net.created_at }
        lag_time = Time.now - (most_stale.last_maintenance_at || most_stale.created_at)
        GitHub.dogstats.histogram("network_maintenance_scheduler.lag", lag_time)

        most_active = networks.max_by { |net| net.pushed_count_since_maintenance }
        GitHub.dogstats.histogram("network_maintenance_scheduler.most-active", most_active.pushed_count_since_maintenance)
      end

      RepositoryNetwork.maintenance_counts.each do |status, network_count|
        GitHub.dogstats.gauge("git_maintenance.count", network_count, tags: ["type:network", "status:#{status}"])
        GitHub.stats.gauge("git_maintenance.network.count.#{status}", network_count) if GitHub.enterprise?
      end

      need_count = RepositoryNetwork.count_over_activity_threshold
      GitHub.dogstats.gauge("git_maintenance.need_maintenance", need_count, tags: ["type:network"])
      GitHub.stats.gauge("git_maintenance.network.count.needed", need_count) if GitHub.enterprise?

      networks
    end
  end
end
