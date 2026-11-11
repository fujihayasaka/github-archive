# typed: true
# frozen_string_literal: true

module Exporter
  class MigrationExportBatchJob < ApplicationJob
    queue_as :exporter_batch

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    MAX_ATTEMPTS = 5

    RETRYABLE_ERRORS = [
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::ConnectionTimeoutError,
      Faraday::TimeoutError,
      GitRPC::Timeout,
    ].freeze

    retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: MAX_ATTEMPTS

    after_discard do |job, error|
      job.handle_failed_batch(error)
    end

    # Public: Perform the export batch job
    #
    # migration_export_batch_id - MigrationExportBatch record to process
    # options                   - Hash of options (exclude_git_data, org_metadata_only, etc.)
    sig { params(migration_export_batch_id: Integer, options: T::Hash[String, T.untyped]).void }
    def perform(migration_export_batch_id, options = {})
      migration_export_batch = claim_batch(migration_export_batch_id)
      return if migration_export_batch.nil? # batch already claimed

      state_manager = Exporter::BatchStateManager.new(
        migration_export_batch: migration_export_batch
      )

      migration = T.must(migration_export_batch.migration)
      if migration.failed?
        abort_batch(migration_export_batch, state_manager)
        return
      end

      # Build export options with explicit defaults
      export_options = Exporter::ExportOptions.new(
        exclude_git_data: options.fetch("exclude_git_data", false),
        org_metadata_only: options.fetch("org_metadata_only", false)
      )

      # Process the batch using BatchProcessor service
      processor = Exporter::BatchProcessor.new(
        migration_export_batch: migration_export_batch,
        options: export_options
      )
      processor.process
    end

    sig { params(migration_export_batch_id: Integer).returns(T.nilable(MigrationExportBatch)) }
    def claim_batch(migration_export_batch_id)
      with_write do
        MigrationExportBatch.transaction do
          migration_export_batch = MigrationExportBatch
            .where(id: migration_export_batch_id, state: MigrationExportBatch.workflow_spec.states[:queued].value)
            .includes(:migration)
            .lock("FOR UPDATE SKIP LOCKED")
            .annotate("cross-schema-domain-query-exempted") # thinks 'skip' is a cross query
            .first

          return nil if migration_export_batch.nil? # already locked or claimed

          state_manager = Exporter::BatchStateManager.new(
            migration_export_batch: migration_export_batch
          )
          state_manager.claim_batch!

          migration_export_batch
        end
      end
    end

    sig { params(migration_export_batch: MigrationExportBatch, state_manager: BatchStateManager).void }
    def abort_batch(migration_export_batch, state_manager)
      state_manager.abort_batch(reason: "Migration is failed")

      GitHub.logger.info("Aborted export batch because migration is failed", {
        "code.namespace" => self.class.name,
        "code.function" => "abort_batch",
        :migration_id => migration_export_batch.migration_id,
        :migration_guid => T.must(migration_export_batch.migration).guid,
        :migration_export_batch_id => migration_export_batch.id
      })
    end

    sig { params(migration_export_batch: MigrationExportBatch, state_manager: BatchStateManager, error: Exception).void }
    def fail_on_error(migration_export_batch, state_manager, error)
      metrics_reporter = Exporter::MetricsReporter.new(
        migration: T.must(migration_export_batch.migration),
        migration_export_batch: migration_export_batch
      )

      metrics_reporter.report_failure
      state_manager.fail_batch(error: error)

      context = {
        "gh.migration_tools.migration_export_batch.id": migration_export_batch.id,
        "gh.migration_tools.migration.id": migration_export_batch.migration_id
      }

      Failbot.report!(error, context)
    end

    sig { params(error: Exception).void }
    def handle_failed_batch(error)
      migration_export_batch = MigrationExportBatch.find_by(id: self.arguments.first)

      return Failbot.report!(error) unless migration_export_batch

      state_manager = Exporter::BatchStateManager.new(
        migration_export_batch: migration_export_batch
      )
      fail_on_error(migration_export_batch, state_manager, error)
    end
  end
end
