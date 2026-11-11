# typed: strict
# frozen_string_literal: true

module Exporter
  # Service for fetching completed export batches for a migration.
  #
  # This service handles pagination and retry logic when fetching completed batches,
  # with the ability to exclude already-processed batch IDs.
  #
  # Example usage:
  #   fetcher = Exporter::CompletedBatchFetcher.new(migration: migration)
  #   fetcher.fetch(processed_ids: Set[1, 2, 3]) do |batch_relation|
  #     batch_relation.each { |batch| ... }
  #   end
  class CompletedBatchFetcher
    DEFAULT_BATCH_SIZE = 1000
    MAX_RETRIES = 5

    sig { params(migration: Migration, batch_size: Integer).void }
    def initialize(migration:, batch_size: DEFAULT_BATCH_SIZE)
      @migration = migration
      @batch_size = batch_size
    end

    # Fetch all completed batches for the migration, optionally excluding already-processed IDs
    # Yields ActiveRecord::Relation of MigrationExportBatch records in batches
    sig { params(processed_ids: T::Set[Integer], block: T.proc.params(arg0: T.untyped).void).void }
    def fetch(processed_ids: Set.new, &block)
      ConnectionRetry.with_retry(
        migration: @migration,
        query_name: :fetch_completed_batches
      ) do
        MigrationExportBatch.throttle_with_retry(max_retry_count: MAX_RETRIES) do
          MigrationExportBatch.uncached do
            completed_state = MigrationExportBatch.workflow_spec.states[:completed].value
            completed_with_failures_state = MigrationExportBatch.workflow_spec.states[:completed_with_failures].value

            query = MigrationExportBatch
              .where(migration_id: @migration.id, state: [completed_state, completed_with_failures_state])
              .includes(:migration)

            # Exclude already processed batch IDs
            query = query.where.not(id: processed_ids.to_a) unless processed_ids.empty?

            query.in_batches(of: @batch_size, &block)
          end
        end
      end
    end
  end
end
