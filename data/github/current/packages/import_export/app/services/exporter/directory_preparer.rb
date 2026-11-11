# typed: strict
# frozen_string_literal: true

module Exporter
  # Service for preparing a directory with all completed export batch files.
  #
  # This service:
  # 1. Fetches all completed export batches for a migration
  # 2. Downloads each batch's MigrationFile from storage
  # 3. Extracts archives into a structured working directory
  # 4. Waits for pending/in-progress batches to complete
  #
  # The prepared directory can then be used by ExportArchiveCreator to create
  # the final archive.
  #
  # Example usage:
  #   preparer = Exporter::DirectoryPreparer.new(
  #     migration: migration,
  #     working_dir: "/tmp/export-work"
  #   )
  #   result = preparer.prepare
  #   # => { successful_ids: [1, 2, 3], failed_ids: [4] }
  class DirectoryPreparer
    # Exception raised when no new batches are found within the timeout period
    class NoActivityTimeoutError < StandardError; end

    MAX_RETRIES = 5
    SLEEP_TIME = T.let(10.seconds, ActiveSupport::Duration)
    # Timeout after 30 minutes of no new batches being found
    NO_ACTIVITY_TIMEOUT = T.let(30.minutes, ActiveSupport::Duration)

    sig do
      params(
        migration: Migration,
        working_dir: Pathname
      ).void
    end
    def initialize(migration:, working_dir:)
      @migration = migration
      @working_dir = working_dir
    end

    sig { returns({ successful_ids: T::Set[Integer], failed_ids: T::Set[Integer] }) }
    def prepare
      # Track successful and failed batch IDs across all iterations
      successful_batch_ids = Set.new
      failed_batch_ids = Set.new

      # Track last time we found new batches for timeout detection
      last_activity_time = Time.current

      # Create fetcher for completed batches
      batch_fetcher = CompletedBatchFetcher.new(migration: @migration)
      migration_tracker = MigrationExportTracker.new(migration: @migration)

      # Process batches incrementally until all are processed
      loop do
        # Get next batch of completed batches, excluding already processed ones
        processed_ids = successful_batch_ids + failed_batch_ids

        has_batches = T.let(false, T::Boolean)

        batch_fetcher.fetch(processed_ids: processed_ids) do |batch_relation|
          has_batches = true

          # Convert relation to array for processing
          batches = batch_relation.to_a

          GitHub.logger.info(
            "DirectoryPreparer: Processing batch group",
            migration_guid: @migration.guid,
            batch_count: batches.size,
            total_successful: successful_batch_ids.size,
            total_failed: failed_batch_ids.size
          )

          # Download and extract this batch group
          batch_preparer = BatchContentPreparer.new(
            batches: batches,
            serialization_dir: @working_dir.join("serialization"),
            archiving_dir: @working_dir,
            actor: T.must(@migration.creator)
          )
          extraction_result = batch_preparer.extract_all

          # Update tracking sets with results from this iteration
          extraction_result[:successful_ids].each { |id| successful_batch_ids.add(id) }
          extraction_result[:failed_ids].each { |id| failed_batch_ids.add(id) }

          # Update activity time since we found and processed batches
          last_activity_time = Time.current

          GitHub.logger.info(
            "DirectoryPreparer: Batch group processed",
            migration_guid: @migration.guid,
            iteration_success_count: extraction_result[:successful_ids].size,
            iteration_failed_count: extraction_result[:failed_ids].size,
            total_successful: successful_batch_ids.size,
            total_failed: failed_batch_ids.size
          )
        rescue StandardError => e
          GitHub.logger.error(
            "DirectoryPreparer: Failed to fetch or process batch group",
            migration_guid: @migration.guid,
            error: e.message,
            backtrace: e.backtrace&.first(5)
          )
        end

        # Check if we've exceeded the no-activity timeout
        time_since_last_activity = Time.current - last_activity_time
        if time_since_last_activity > NO_ACTIVITY_TIMEOUT
          error_message = "No new batches found for #{time_since_last_activity.to_i} seconds (timeout: #{NO_ACTIVITY_TIMEOUT.to_i} seconds)"
          GitHub.logger.error(
            "DirectoryPreparer: No activity timeout reached",
            migration_guid: @migration.guid,
            migration_id: @migration.id,
            time_since_last_activity_seconds: time_since_last_activity.to_i,
            timeout_seconds: NO_ACTIVITY_TIMEOUT.to_i
          )
          raise NoActivityTimeoutError, error_message
        end

        # If no completed batches, check if there are any in-progress batches
        unless has_batches
          has_active_batches = false

          begin
            has_active_batches = migration_tracker.has_active_batches?
          rescue StandardError => e
            # On any failure checking for active batches, assume there might be batches and continue
            GitHub.logger.error(
              "DirectoryPreparer: Failed to check for active batches, assuming batches exist",
              migration_guid: @migration.guid,
              error: e.message,
              backtrace: e.backtrace&.first(5)
            )
            # Continue waiting (don't break)
            has_active_batches = true
          end

          # Break if no batches are pending or in-progress
          break unless has_active_batches

          # Wait for batches to complete
          GitHub.logger.info(
            "DirectoryPreparer: No completed batches, waiting for pending or in-progress batches",
            migration_guid: @migration.guid,
            has_active_batches: has_active_batches
          )
          sleep(SLEEP_TIME.to_i) # Wait before checking again
          next
        end
      end

      GitHub.logger.info(
        "DirectoryPreparer: All batches processed",
        migration_guid: @migration.guid,
        total_success_count: successful_batch_ids.size,
        total_failed_count: failed_batch_ids.size
      )

      # Move serialization files into final directory structure
      move_serialization_files

      { successful_ids: successful_batch_ids, failed_ids: failed_batch_ids }
    end

    private

    # Move serialization files from model type directories to final structure
    sig { void }
    def move_serialization_files
      serialization_dir = @working_dir.join("serialization")

      # Get all model types from MIGRATABLE_MODELS
      model_types = GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.map do |mm|
        mm.model_type.classify
      end

      mover = SerializationFileMover.new(
        source_dir: serialization_dir,
        target_dir: @working_dir,
        model_types: model_types
      )

      result = mover.move_files

      GitHub.logger.info(
        "DirectoryPreparer: Serialization files moved",
        migration_guid: @migration.guid,
        files_moved: result[:files_moved],
        moves_by_model_type: result[:moves_by_model_type]
      )

      # Delete the serialization directory after moving files
      FileUtils.rm_rf(serialization_dir) if serialization_dir.exist?
    end
  end
end
