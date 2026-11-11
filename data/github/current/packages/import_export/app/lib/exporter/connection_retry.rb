# typed: strict
# frozen_string_literal: true

module Exporter
  # Handles retrying operations that may fail due to database connection issues
  class ConnectionRetry
    MAX_RETRIES = 5

    RETRYABLE_ERRORS = [
      ActiveRecord::ConnectionFailed,
      ActiveRecord::StatementInvalid,
      ActiveRecord::ConnectionTimeoutError
    ].freeze

    sig do
      type_parameters(:T)
        .params(
          migration: Migration,
          query_name: Symbol,
          migration_export_batch: T.nilable(MigrationExportBatch),
          max_retries: Integer,
          blk: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
    end
    def self.with_retry(migration:, query_name:, migration_export_batch: nil, max_retries: MAX_RETRIES, &blk)
      retry_count = 0
      migration_guid = migration.guid

      # Create MetricsReporter for this operation
      metrics_reporter = MetricsReporter.new(
        migration: migration,
        migration_export_batch: migration_export_batch
      )

      begin
        blk.call
      rescue *RETRYABLE_ERRORS => e
        retry_count += 1

        if retry_count <= max_retries
          GitHub.logger.warn(
            "Database operation failed with #{e.class.name}: #{e.message}, will retry",
            migration_guid: migration_guid,
            retry_count: retry_count,
            error_class: e.class.name
          )

          sleep(2**(retry_count - 1)) # Exponential backoff
          retry
        else
          GitHub.logger.error(
            "Database operation failed with #{e.class.name} after max retries: #{e.message}",
            migration_guid: migration_guid,
            retry_count: retry_count,
            error_class: e.class.name,
            query_name: query_name
          )

          metrics_reporter.report_connection_retry_exhausted(
            query_name: query_name,
            error_class: T.must(e.class.name)
          )

          raise
        end
      end
    end
  end
end
