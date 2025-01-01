# typed: true
# frozen_string_literal: true

class ImportArchiveJob < ApplicationJob
  use_primaries ApplicationRecord::Migrations

  queue_as :dotcom_importer

  # This job auto retries on Aqueduct::Worker::JobKilled due to
  # memory issues documented in https://github.com/github/github/issues/179568. This exception
  # typically gets raised after processing 17K review comments, typically retrying this job once or twice
  # is enough but the max attempt retries specified below
  # should cover mid to large size migrations (17K * 20 = 340K review comments).
  #
  # It also now retries on ActiveRecord::ConnectionFailed, which
  # occurs sporadically and is non-actionable from an application perspective.
  MAX_ATTEMPTS = 20
  FRENO_RETRY_ATTEMPTS = 10

  RETRYABLE_ERRORS = [
    ActiveRecord::Deadlocked,
    ActiveRecord::QueryCanceled,
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::NoDatabaseError,
    ActiveRecord::StatementInvalid,
    Aqueduct::Worker::JobKilled,
    Faraday::TimeoutError,
    GitRPC::Timeout,
    ActiveRecord::ConnectionFailed,
  ].freeze

  discard_on StandardError do |job, error|
    # Set migration state to :failed_import
    job.fail_migration_and_raise(error)
  end

  retry_on Freno::Throttler::WaitedTooLong, attempts: FRENO_RETRY_ATTEMPTS do |job, error|
    migration = job.arguments.first

    GitHub.logger.error("Setting migration to failed, Exhausted replication delay retries",
      {
        :exception => error,
        "gh.job.retries" => job.executions,
        "code.function" => "retry_on",
        "code.namespace" => "ImportArchiveJob",
        "gh.migration_tools.migration.type" => "repo",
        "gh.migration_tools.migration.guid" => migration.guid
        }
      )

    job.fail_migration_and_raise(error)
  end

  retry_on *RETRYABLE_ERRORS, attempts: MAX_ATTEMPTS do |job, error|
    migration = job.arguments.first

    GitHub.logger.error(
      "Setting migration to failed, Exhausted dirty exit retries ",
      {
        "gh.job.retries" => job.executions,
        "code.namespace" => "ImportArchiveJob",
        "code.function" => "retry_on",
        "gh.migration_tools.migration.type" => "repo",
        "gh.migration_tools.migration.guid" => migration.guid
      }
    )

    job.fail_migration_and_raise(error)
  end

  before_enqueue do |job|
    migration = self.arguments.first

    GitHub.logger.info("running before enqueue",
      {
        "gh.job.retries" => job.executions,
        "code.namespace" => "ImportArchiveJob",
        "code.function" => "before_enqueue",
        "gh.migration_tools.migration.type" => "repo",
        "gh.migration_tools.migration.guid" => migration.guid
      }

    )
    job.enqueue_migration
  end

  def perform(migration, actor)
    # Set failbot context
    Failbot.push("gh.migration_tools.migration.id" => migration.id, "gh.migration_tools.migration.owner_id" => migration.owner_id)

    # Set state to importing
    migration.safely_change_migration_state!(:begin_import!) unless migration.importing?

    GitHub.migrator.import(migration, actor)

    migration.complete_import!

    send_completion_metrics!("migrator.import.success")

  rescue Aqueduct::Worker::JobKilled => error
    tags = ["migrator_pid:#{process_id}", "migration_guid:#{migration.guid}"]
    GitHub.dogstats.increment("migrator.import.job_killed", tags: tags)
    GitHub.logger.error("Detected dirty exit, re-raising for retry",
      {
        :exception => error,
        "code.namespace" => "ImportArchiveJob",
        "gh.migration_tools.migration.type" => "repo",
        "gh.migration_tools.migration.guid" => migration.guid
      }
    )

    raise
  rescue Freno::Throttler::WaitedTooLong => error
    tags = ["migration_guid:#{migration.guid}"]
    GitHub.dogstats.increment("migrator.import.throttler_error_retry", tags: tags)
    GitHub.logger.error("Detected freno throttler error, re-raising for retry",
      {
        :exception => error,
        "code.namespace" => "ImportArchiveJob",
        "code.function" => "perform",
        "gh.migration_tools.migration.type" => "repo",
        "gh.migration_tools.migration.guid" => migration.guid
      }
    )

    raise
  rescue ActiveRecord::StatementInvalid => error
    tags = ["migration_guid:#{migration.guid}"]
    GitHub.dogstats.increment("migrator.import.post_processing_failures", tags: tags)

    # Retry exceptions that aren't tied to queries exploding during post processing
    raise unless error.message.match(/ResourceExhausted desc = grpc: trying to send message larger than max/)

    # Report original exception to sentry
    Failbot.report!(error)

    # Log exception to splunk
    log_message = "Migration failed due to aborted SQL query that attempted to fetch too many models." \
    "Check sentry for additional details on original exception." \
    "To get around this, consider enabling the :gh_migrator_skip_post_processor_joins feature flag against the migration actor."

    GitHub.logger.error(
      log_message,
      :exception => error,
      "code.function" => "perform",
      "code.namespace" => "ImportArchiveJob",
      "gh.migration_tools.migration.type" => "repo",
      "gh.migration_tools.migration.guid" => migration.guid
    )

    # Re-raise as ResourceExhaustedError so that migration fails
    raise GitHub::Migrator::ResourceExhaustedError.new(log_message)
  end

  def enqueue_migration
    migration = self.arguments.first
    migration.failed_import? ? migration.retry_import! : migration.import!
  end

  def fail_migration_and_raise(error)
    migration = self.arguments.first
    migration.force_failed_import!

    send_completion_metrics!("migrator.import.failure")

    Failbot.report!(error)
    raise error
  end

  private

  def tags
    @tags ||= begin
      migration = self.arguments.first
      [
        "guid:#{migration.guid}",
        "owner_id:#{migration.owner_id}",
      ]
    end
  end

  def send_completion_metrics!(metric)
    GitHub.dogstats.increment(metric, tags: tags)
  end

  def process_id
    $$
  end
end
