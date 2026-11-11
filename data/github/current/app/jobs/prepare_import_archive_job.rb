# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PrepareImportArchiveJob < ApplicationJob
  queue_as :prepare_import_archive

  retry_on Freno::Throttler::WaitedTooLong

  discard_on StandardError do |job, error|
    # Set migration state to :failed
    job.fail_migration_and_raise(error)
  end

  before_enqueue do |job|
    job.enqueue_migration
  end

  def perform(migration, actor)
    # Set failbot context
    Failbot.push("gh.migration_tools.migration.id" => migration.id)

    # Set state to preparing
    unless migration.preparing?
      with_write { migration.begin_prepare! }
    end

    with_write { GitHub.migrator.prepare(migration, actor) }
  rescue Freno::Throttler::WaitedTooLong => error
    tags = ["guid:#{migration.guid}"]
    GitHub.dogstats.increment("migrator.prepare.throttler_error_retry", tags: tags)
    GitHub.logger.error("Detected freno throttler error, re-raising for retry", {
      exception: error,
      "code.function": __method__,
      "code.namespace": "PrepareImportArchiveJob",
      "gh.migration_tools.migration.guid": migration.guid,
     }
    )
    raise
  end

  def enqueue_migration
    migration = self.arguments.first
    with_write { migration.prepare! }
  end

  def fail_migration_and_raise(error)
    migration = self.arguments.first
    with_write { migration.failed! }

    Failbot.report!(error)
    raise error
  end
end
