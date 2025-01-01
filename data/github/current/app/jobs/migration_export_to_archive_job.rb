# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MigrationExportToArchiveJob < ApplicationJob
  queue_as :gh_migrator

  discard_on StandardError do |job, error|
    job.fail_migration_and_raise(error)
  end

  MAX_ATTEMPTS = 5

  RETRYABLE_ERRORS = [
    GitHub::Migrator::EmptyMigration,
    ActiveRecord::Deadlocked,
    ActiveRecord::QueryCanceled,
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::NoDatabaseError,
    ActiveRecord::StatementInvalid,
    Aqueduct::Worker::JobKilled,
    Faraday::TimeoutError,
    GitRPC::Timeout,
    ActiveRecord::ConnectionFailed,
    WaitForReplication::DataUnavailable
  ].freeze

  retry_on Freno::Throttler::Error

  retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |job, error|
    job.fail_migration_and_raise(error)
  end

  def perform(migration, include_timestamp: false)
    # Set failbot context
    Failbot.push("gh.migration_tools.migration.id" => migration.id)

    # Set migration state to :exporting
    with_write { migration.exporting! }

    GitHub::Timer.timeout(GitHub.max_gh_migrator_export_time, GitHub::Migrator::TimeoutError) do
      with_write { GitHub.migrator.export(migration, include_timestamp: include_timestamp) }
    end

    # Set migration state to :exported
    with_write do
      if ::Migration.export_disabled_for_actor?(migration.creator)
        ::Migration.enable_export_for_actor(migration.creator)
      else
        migration.exported!
        send_completion_metrics!("migrator.export.success")
        send_file_size_metrics!(true)
        send_timing_metrics!("migration.export.end_to_end_duration", started_at: migration.created_at, succeeded: true)
      end
    end
  rescue Aqueduct::Worker::JobKilled => error
    tags = ["migration_guid:#{migration.guid}"]
    GitHub.dogstats.increment("migrator.export.job_killed", tags: tags)
    GitHub.logger.error("Detected dirty exit, re-raising for retry",
      {
        :exception => error,
        "code.function" => __method__,
        "code.namespace" => "MigrationExportToArchiveJob",
        "gh.migration_tools.migration.guid" => migration.guid
      }
    )

    raise
  end

  def fail_migration_and_raise(error)
    migration = self.arguments.first
    with_write { migration.failed! }

    send_completion_metrics!("migrator.export.failure")
    send_file_size_metrics!(false)
    send_timing_metrics!("migration.export.end_to_end_duration", started_at: migration.created_at, succeeded: false)
    Failbot.report!(error)
    raise error
  end

  private

  def send_completion_metrics!(metric)
    migration_guid = self.arguments.first&.guid
    GitHub.dogstats.increment(metric, tags: ["guid:#{migration_guid}", "queue_name:#{queue_name}"])
  end

  def send_file_size_metrics!(export_succeeded)
    migration_guid = self.arguments.first&.guid
    migration_file_size = self.arguments.first&.file&.size.present? ? self.arguments.first&.file.size : 0
    GitHub.dogstats.gauge(
      "migration.export.file.size",
      migration_file_size,
      tags: [
        "guid:#{migration_guid}",
        "export_succeeded:#{export_succeeded}",
        "queue_name:#{queue_name}"
      ]
    )
  end

  def send_timing_metrics!(metric, started_at:, succeeded:)
    elapsed_time_in_ms = GitHub::Dogstats.duration(started_at)
    GitHub.dogstats.timing(metric, elapsed_time_in_ms, tags: ["succeeded:#{succeeded}"])
  end
end
