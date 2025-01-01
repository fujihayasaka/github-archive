# typed: true
# frozen_string_literal: true

class MapImportRecordsJob < ApplicationJob
  queue_as :map_import_records

  retry_on Freno::Throttler::ClientError
  retry_on_dirty_exit

  discard_on StandardError do |job, error|
    job.fail_migration_and_raise(error)
  end

  def perform(migration, mappings, actor)
    # Set failbot context
    Failbot.push("gh.migration_tools.migration.id" => migration.id)

    # Set state to "mapping" from "pending"
    unless migration.mapping?
      with_write { migration.begin_map! }
    end

    GitHub::Timer.timeout(GitHub.max_gh_migrator_export_time, GitHub::Migrator::TimeoutError) do
      with_write { GitHub.migrator.map(migration, mappings, actor) }
    end
  rescue Freno::Throttler::ClientError => error
    tags = ["guid:#{migration.guid}"]
    GitHub.dogstats.increment("migrator.map.throttler_error_retry", tags: tags)
    GitHub.logger.error(
      "Detected freno throttler error, re-raising for retry",
      {
        :exception => error,
        "code.function" => "perform",
        "code.namespace" => "MapImportRecordsJob",
        "gh.migration_tools.migration.type" => "repo",
        "gh.migration_tools.migration.guid" => migration.guid
      }
    )
    raise
  end

  def fail_migration_and_raise(error)
    migration = self.arguments.first
    with_write { migration.failed! }

    Failbot.report!(error)
    raise error
  end
end
