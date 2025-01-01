# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MigrationEnqueueDestroyFileJobsJob < ApplicationJob
  retry_on_dirty_exit

  schedule interval: 1.hour

  queue_as :migration_enqueue_destroy_file_jobs

  DAYS_TO_KEEP_FILES = 7

  # Don't queue more than 5k jobs at a time to protect from running too many jobs
  MAX_QUEUED_JOBS = 5000

  # Queue jobs for migration files that should be removed.
  def perform
    queued_count = 0

    MigrationFile.older_than(DAYS_TO_KEEP_FILES.days.ago).find_each do |file|
      break if queued_count == MAX_QUEUED_JOBS

      MigrationDestroyFileJob.perform_later("migration_id" => file.migration_id)

      T.must(file.migration).clean_up if GitHub.flipper[:destroy_migratable_resources_with_migration_file].enabled? && file.migration

      queued_count += 1
    end
  end
end
