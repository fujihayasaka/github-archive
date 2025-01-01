# typed: true
# frozen_string_literal: true

require "scientist"

class GitbackupsMigrationSchedulerJob < ApplicationJob
  queue_as :gitbackups_migration_scheduler

  # Adjust as the number of networks and workers changes
  schedule interval: 30.minutes, condition: -> { GitHub.realtime_backups_enabled? && !GitHub.single_or_multi_tenant_enterprise? }

  MAINTENANCE_JOB_THRESHOLD = 500

  def queue_length
    GitbackupsMaintenanceJob.queue_depth
  end

  # Run every interval.
  def perform
    Failbot.push app: "gitbackups"

    return if queue_length > MAINTENANCE_JOB_THRESHOLD

    # We give each kind a budget of 250
    budget = 250

    schedule_networks(budget)

    schedule_wikis(budget)

    schedule_gists(budget)
  end

  # Schedule up to +max+ networks for storage migration
  def schedule_networks(max)
    schedule_migration("networks", max: max)
  end

  # Schedule up to +max+ wikis for storage migration
  def schedule_wikis(max)
    schedule_migration("wikis", max: max)
  end

  # Schedule up to +max+ gists for storage migration
  def schedule_gists(max)
    schedule_migration("gists", max: max)
  end

  # Returns which networks need storage migration.
  #
  # max - maximum number of results to return
  def schedule_migration(repo_type, max: 20)
    needing_migration = GitHub::Backups.need_migration(repo_type, max: max)

    GitHub::Logger.log_context(job: self.class.to_s) do
      GitHub::Backups.schedule_migration(needing_migration)
    end

    needing_migration.length
  end
end
