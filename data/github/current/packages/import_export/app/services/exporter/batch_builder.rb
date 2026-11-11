# typed: strict
# frozen_string_literal: true

module Exporter
  # Builder for creating and queueing export batches for a migration.
  # This builder handles:
  # - Building lists of model IDs to export
  # - Creating MigrationExportBatch records
  # - Queueing MigrationExportBatchJob for processing
  class BatchBuilder
    # Number of models to include in each batch
    BATCH_SIZE = 1000
    DEFAULT_PROGRESS = T.let(lambda { |_type, _value| }, T.proc.params(type: Symbol, count: Integer).void)

    # Archiver-specific batch sizes for splitting archiving batches
    # These smaller sizes allow for better parallelization and resource management
    ARCHIVER_BATCH_SIZES = T.let({
      "repository" => 1,            # Repositories are large, process one at a time
      "attachment" => 100,          # Attachments are medium-sized
      "release" => 10,              # Releases can contain many assets
      "repository_file" => 100,     # Files are typically small
    }.freeze, T::Hash[String, Integer])

    sig do
      params(
        migration: Migration,
        options: ExportOptions,
        progress: T.proc.params(type: Symbol, count: Integer).void,
        batch_size: Integer
      ).void
    end
    def initialize(migration:, options: ExportOptions.new, progress: DEFAULT_PROGRESS, batch_size: BATCH_SIZE)
      @migration = migration
      @options = options
      @progress = progress
      @batch_size = batch_size
      @batches = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[String, T::Array[Integer]])
      @metrics_reporter = T.let(MetricsReporter.new(migration: @migration), MetricsReporter)
    end

    sig { params(model: ApplicationRecord::Base).void }
    def add_model(model)
      model_type = model.class.model_name.to_s.underscore

      begin
        # Validate that this is a migratable model type
        MigratableModelResolver.resolve(model_type)
      rescue ArgumentError => e
        GitHub.logger.warn("Skipping non-migratable model type",
          migration_guid: @migration.guid, migration_id: @migration.id, model_type: model_type, error: e.message
        )

        # Report metric for non-migratable model type
        @metrics_reporter.report_non_migratable_model(model_type: model_type, error_message: e.message)

        return
      end

      model_exist = @metrics_reporter.with_duration(operation: :model_exists_cache_hit) do
        GitHub.cache.get(cache_key(model_type, model.id))
      end

      return if model_exist

      model_url_service = GitHub::Migrator::ModelUrlService.new(
        cache: Services::MigratorCacheAdapter.new(migration_guid: @migration.guid)
      )
      GitHub.cache.set(cache_key(model_type, model.id), model_url_service.url_for_model(model))

      # Track model addition
      @metrics_reporter.report_model_added(model_type: model_type)

      T.must(@batches[model_type]) << model.id

      # Automatically queue a batch if we've reached the batch size
      if T.must(@batches[model_type]).size >= @batch_size
        queue_full_batches(model_type)
      end
    end

    sig { void }
    def queue_batches
      # Queue any remaining batches that haven't been queued yet
      @batches.each do |model_type, model_ids|
        next if model_ids.empty?

        # Create batches of model IDs
        model_ids.each_slice(@batch_size) do |batch_model_ids|
          queue_batch(model_type, batch_model_ids)
        end

        # Clear the batches after queueing
        model_ids.clear
      end
    end

    sig { params(model_type: String).void }
    def flush_batches_for(model_type)
      model_ids = @batches[model_type]
      return if model_ids.nil? || model_ids.empty?

      # Queue all remaining batches for this model type
      model_ids.each_slice(@batch_size) do |batch_model_ids|
        queue_batch(model_type, batch_model_ids)
      end

      # Clear the batches after queueing
      model_ids.clear
    end

    private

    sig { params(model_type: String, model_id: Integer).returns(String) }
    def cache_key(model_type, model_id)
      "migration:#{@migration.guid}:#{model_type}:#{model_id}"
    end

    sig { params(model_type: String).void }
    def queue_full_batches(model_type)
      model_ids = T.must(@batches[model_type])

      # Queue complete batches and keep the remainder
      while model_ids.size >= @batch_size
        batch_to_queue = model_ids.shift(@batch_size)
        queue_batch(model_type, batch_to_queue)
      end
    end

    sig { params(model_type: String, batch_model_ids: T::Array[Integer]).void }
    def queue_batch(model_type, batch_model_ids)
      begin
        migratable_model = MigratableModelResolver.resolve(model_type)
        has_archiver = !migratable_model.archiver.nil?

        # Shared params for batch creation
        batch_params = {
          migration: @migration,
          model_type: model_type,
          model_ids: batch_model_ids,
        }

        serialization_batch = T.let(nil, T.nilable(MigrationExportBatch))
        archiving_batches = T.let([], T::Array[MigrationExportBatch])

        ConnectionRetry.with_retry(
          migration: @migration,
          query_name: :batch_creation
        ) do
          ActiveRecord::Base.connected_to(role: :writing) do
            MigrationExportBatch.transaction do
              # Always create serialization batch
              serialization_batch = MigrationExportBatch.create!(
                **batch_params,
                type: :serialization
              )

              # Create archiving batches if model has an archiver
              # Split into smaller batches based on ARCHIVER_BATCH_SIZES
              if has_archiver
                archiver_batch_size = ARCHIVER_BATCH_SIZES[model_type] || @batch_size

                # Split the batch_model_ids into smaller chunks for archiving
                batch_model_ids.each_slice(archiver_batch_size) do |archiver_model_ids|
                  archiving_batch = MigrationExportBatch.create!(
                    **batch_params.merge(model_ids: archiver_model_ids),
                    type: :archiving
                  )
                  archiving_batches << archiving_batch
                end
              end
            end
          end
        end

        # Always queue serialization job
        MigrationExportBatchJob.perform_later(T.must(serialization_batch).id, @options.serialize)

        # Queue archiving jobs for each archiving batch
        archiving_batches.each do |archiving_batch|
          MigrationExportBatchJob.set(queue: :exporter_batch_with_storage).perform_later(archiving_batch.id, @options.serialize)
        end

        # Track batch creation
        @metrics_reporter.report_batch_queued(model_type: model_type, batch_type: :serialization)

        # Report progress for serialization batch
        @progress.call(:progress_with_count, batch_model_ids.size)

        # Track archiving batch creation for each batch created
        archiving_batches.each do |archiving_batch|
          @metrics_reporter.report_batch_queued(model_type: model_type, batch_type: :archiving)

          # Report progress for archiving batch
          @progress.call(:progress_with_count, archiving_batch.model_ids.size)
        end
      rescue StandardError => e
        GitHub.logger.error(
          "Failed to create batch after retries, skipping",
          migration_guid: @migration.guid,
          model_type: model_type,
          batch_size: batch_model_ids.size,
          error: e.message
        )
      end
    end
  end
end
