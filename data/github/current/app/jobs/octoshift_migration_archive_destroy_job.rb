# typed: true
# frozen_string_literal: true

class OctoshiftMigrationArchiveDestroyJob < ApplicationJob
  retry_on_dirty_exit

  queue_as :octoshift_migration_archive_destroy_job

  # Public: Delete the archive for the migration.
  #
  # migration_id - The id of a Migration.
  def perform(options)
    octoshift_migration_archive_id = options.fetch("octoshift_migration_archive_id")
    Failbot.push("gh.migration_tools.octoshift_migration_archive.id" => octoshift_migration_archive_id)
    octoshift_migration_archive = OctoshiftMigrationArchive.find(octoshift_migration_archive_id)
    # this will call storage_delete_object
    with_write { octoshift_migration_archive.destroy }
  end
end
