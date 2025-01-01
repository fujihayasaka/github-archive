# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EnqueueOctoshiftMigrationArchiveDestroyJobsJob < ApplicationJob
  retry_on_dirty_exit

  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  queue_as :enqueue_octoshift_migration_archive_destroy_jobs

  DAYS_TO_KEEP_FILES = 7

  # Don't queue more than 5k jobs at a time to protect from running too many jobs
  MAX_QUEUED_JOBS = 5000

  # Queue jobs for migration files that should be removed.
  def perform
    queued_count = 0

    OctoshiftMigrationArchive.where(created_at: ..DAYS_TO_KEEP_FILES.days.ago).find_each do |archive|
      break if queued_count == MAX_QUEUED_JOBS

      OctoshiftMigrationArchiveDestroyJob.perform_later("octoshift_migration_archive_id" => archive.id)

      queued_count += 1
    end
  end
end
