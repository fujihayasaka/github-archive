# typed: strict
# frozen_string_literal: true

require "parallel"

module Exporter
  # Service for downloading and extracting export batches into organized directories.
  #
  # This service handles:
  # 1. Downloading batch files using BatchDownloader
  # 2. For serialization batches, organizing by model type directory
  # 3. For archiving batches, extracting files as-is
  # 4. Extracting archives into the appropriate directories
  #
  # Directory structure for serialization:
  #   {serialization_dir}/{model_type_snake_case}/
  #     {files from archive}
  #
  # Directory structure for archiving:
  #   {archiving_dir}/
  #     {extracted_files}
  #
  # Example usage:
  #   preparer = Exporter::BatchContentPreparer.new(
  #     batches: batches,
  #     serialization_dir: working_dir.join("serialization"),
  #     archiving_dir: working_dir,
  #     actor: user
  #   )
  #   result = preparer.extract_all
  #   # => { successful_ids: [1, 2, 3], failed_ids: [4] }
  class BatchContentPreparer
    PROCESS_COUNT = 5

    sig do
      params(
        batches: T::Array[MigrationExportBatch],
        serialization_dir: Pathname,
        archiving_dir: Pathname,
        actor: User
      ).void
    end
    def initialize(batches:, serialization_dir:, archiving_dir:, actor:)
      @batches = batches
      @serialization_dir = serialization_dir
      @archiving_dir = archiving_dir
      @actor = actor
    end

    # Download and extract all batches to the destination directory
    # Returns a hash with successful_ids and failed_ids
    sig { returns({ successful_ids: T::Array[Integer], failed_ids: T::Array[Integer] }) }
    def extract_all
      # Capture values needed in child processes
      actor_id = @actor.id
      serialization_dir = @serialization_dir
      archiving_dir = @archiving_dir
      batch_ids = @batches.map(&:id)

      results = ::Parallel.map(batch_ids, in_processes: PROCESS_COUNT) do |batch_id|
        # Re-fetch batch and actor in child process (processes don't share ActiveRecord objects)
        batch = MigrationExportBatch.find(batch_id)
        actor = User.find(actor_id)

        if extract_batch(batch, actor: actor, serialization_dir: serialization_dir, archiving_dir: archiving_dir)
          [:success, batch.id]
        else
          [:failed, batch.id]
        end
      end

      # Separate success and failure IDs
      successful_ids = results.select { |status, _| status == :success }.map { |_, id| id }
      failed_ids = results.select { |status, _| status == :failed }.map { |_, id| id }

      { successful_ids: successful_ids, failed_ids: failed_ids }
    end
    # Download and extract a single batch
    # Returns true if successful, false otherwise
    sig do
      params(
        batch: MigrationExportBatch,
        actor: User,
        serialization_dir: Pathname,
        archiving_dir: Pathname
      ).returns(T::Boolean)
    end
    def extract_batch(batch, actor:, serialization_dir:, archiving_dir:)
      downloader = BatchDownloader.new(batch: batch, actor: actor)
      temp_file_path = downloader.download

      return false unless temp_file_path

      begin
        # Determine destination directory
        if batch.serialization?
          # For serialization: extract to {serialization_dir}/{model_type_snake_case}/ directory
          model_type_snake = batch.model_type.underscore
          destination_dir = serialization_dir.join(model_type_snake)
        else
          # For archiving: extract to archiving directory as-is
          destination_dir = archiving_dir
        end

        FileUtils.mkdir_p(destination_dir)

        GitHub.logger.info(
          "Extracting batch file",
          migration_guid: batch.migration&.guid,
          batch_id: batch.id,
          model_type: batch.model_type,
          type: batch.type,
          destination: destination_dir.to_s
        )

        extractor = ArchiveExtractor.new(
          archive_path: temp_file_path,
          destination_dir: destination_dir,
        )
        extractor.extract

        true
      rescue StandardError => e
        GitHub.logger.error(
          "Failed to extract batch file, continuing",
          migration_guid: batch.migration&.guid,
          batch_id: batch.id,
          model_type: batch.model_type,
          type: batch.type,
          error: e.message,
          backtrace: e.backtrace&.first(5)
        )
        false
      ensure
        File.unlink(temp_file_path) if File.exist?(temp_file_path)
      end
    end
  end
end
