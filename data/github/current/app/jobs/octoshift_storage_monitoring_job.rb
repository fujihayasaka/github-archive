# typed: true
# frozen_string_literal: true

class OctoshiftStorageMonitoringJob < ApplicationJob
  retry_on_dirty_exit

  queue_as :octoshift_storage_monitoring_job
  schedule interval: 10.minutes, condition: -> { !GitHub.enterprise? }

  # Public: Emit a metric for the total size of all migration archives for an organization.
  def perform
    OctoshiftMigrationArchive.group(:organization_id).sum(:size).each do |organization_id, size|
      GitHub.dogstats.gauge(
        "gh.migration_tools.octoshift_migration_archive.total_size",
        size,
        tags: ["org_id:#{organization_id}"],
      )
    end

    OctoshiftMigrationArchive.group(:organization_id).count.each do |organization_id, count|
      GitHub.dogstats.gauge(
        "gh.migration_tools.octoshift_migration_archive.total_count",
        count,
        tags: ["org_id:#{organization_id}"],
      )
    end
  end
end
