# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MigrationDestroyFileJob < ApplicationJob
  retry_on_dirty_exit

  queue_as :migration_destroy_file

  # Queue a migration for archive deletion
  def self.enqueue(migration)
    MigrationDestroyFileJob.perform_later("migration_id" => migration.id)
  end

  # Public: Delete the archive for the migration.
  #
  # migration_id - The id of a Migration.
  def perform(options)
    migration_id = options.fetch("migration_id")
    Failbot.push("gh.migration_tools.migration.id" => migration_id)
    migration = ::Migration.find(migration_id)
    with_write { migration.destroy_file }
  end
end
