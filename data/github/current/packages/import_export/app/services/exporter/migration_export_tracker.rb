# typed: strict
# frozen_string_literal: true

module Exporter
  # Service for tracking the status of a migration export.
  #
  # This service checks if there are pending or in-progress export batches
  # for a migration, which indicates the export is still active.
  #
  # Example usage:
  #   tracker = Exporter::MigrationExportTracker.new(migration: migration)
  #   tracker.has_active_batches?
  #   # => true if there are pending or in-progress batches
  class MigrationExportTracker
    MAX_RETRIES = 5

    sig { params(migration: Migration).void }
    def initialize(migration:)
      @migration = migration
    end

    # Check if there are any pending or in-progress batches for the migration
    sig { returns(T::Boolean) }
    def has_active_batches?
      ConnectionRetry.with_retry(
        migration: @migration,
        query_name: :check_active_batches
      ) do
        MigrationExportBatch.throttle_with_retry(max_retry_count: MAX_RETRIES) do
          MigrationExportBatch.uncached do
            processing_state = MigrationExportBatch.workflow_spec.states[:processing].value
            pending_state = MigrationExportBatch.workflow_spec.states[:pending].value
            queued_state = MigrationExportBatch.workflow_spec.states[:queued].value
            MigrationExportBatch
              .where(migration_id: @migration.id, state: [processing_state, pending_state, queued_state])
              .exists?
          end
        end
      end
    end
  end
end
