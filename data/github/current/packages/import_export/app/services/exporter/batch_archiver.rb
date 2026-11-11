# typed: strict
# frozen_string_literal: true

module Exporter
  # BatchArchiver handles the archiving of multiple models using an archiver instance.
  # It fetches models from the database in batches and processes each model individually,
  # tracking successes and failures.
  class BatchArchiver

    # Result object returned by archiver
    class Result < T::Struct
      const :success_count, Integer
      const :failed_count, Integer
      const :archiving_errors, MigrationExportBatch::ModelProcessingErrors
    end

    # Batch size for loading models from database
    BATCH_SIZE = 100

    MAX_RETRIES = 5

    sig do
      params(
        model_ids: T::Array[Integer],
        model_class: T.class_of(ApplicationRecord::Base),
        archiver: GitHub::Migrator::BaseArchiver,
        migration_export_batch: MigrationExportBatch
      ).void
    end
    def initialize(model_ids:, model_class:, archiver:, migration_export_batch:)
      @model_ids = model_ids
      @model_class = model_class
      @archiver = archiver
      @migration_export_batch = migration_export_batch

      model_type = T.must(model_class.name).underscore
      @scope_service = T.let(
        ArchiverScope.new(model_type: model_type),
        ArchiverScope
      )
    end

    sig { returns(Result) }
    def archive
      success_count = 0
      failed_count = 0
      archiving_errors = T.let({}, MigrationExportBatch::ModelProcessingErrors)

      @model_ids.each_slice(BATCH_SIZE) do |id_batch|
        models = load_batch(id_batch, archiving_errors)
        unless models
          failed_count += id_batch.size
          next
        end

        # Process models sequentially
        models.each do |model|
          begin
            @archiver.save(model)
            success_count += 1
          rescue StandardError => e
            failed_count += 1
            archiving_errors[model.id] = MigrationExportBatch::CapturedError.new(
              error_class: e.class,
              error_message: e.message
            )

            GitHub.logger.warn(
              "Failed to archive model",
              model_id: model.id,
              model_class: @model_class.name,
              error: e.message,
              migration_export_batch_id: @migration_export_batch.id,
              migration_id: T.must(@migration_export_batch.migration).id,
              migration_guid: T.must(@migration_export_batch.migration).guid
            )
          end
        end
      end

      Result.new(
        success_count: success_count,
        failed_count: failed_count,
        archiving_errors: archiving_errors
      )
    end

    private

    sig do
      params(
        id_batch: T::Array[Integer],
        archiving_errors: MigrationExportBatch::ModelProcessingErrors
      ).returns(T.nilable(T::Array[ApplicationRecord::Base]))
    end
    def load_batch(id_batch, archiving_errors)
      ConnectionRetry.with_retry(
        migration: T.must(@migration_export_batch.migration),
        query_name: :load_archiving_batch,
        migration_export_batch: @migration_export_batch
      ) do
        @model_class.throttle_with_retry(max_retry_count: MAX_RETRIES) do
          scope = @scope_service.scope
          @model_class.where(id: id_batch).merge(scope).to_a
        end
      end
    rescue StandardError => e
      # If batch query fails due to other errors after retries, record errors for all IDs in the batch and continue
      GitHub.logger.error(
        "Failed to load batch after retries, skipping",
        migration_guid: T.must(@migration_export_batch.migration).guid,
        model_class: @model_class.name,
        batch_size: id_batch.size,
        error: e.message
      )
      id_batch.each do |id|
        archiving_errors[id] = MigrationExportBatch::CapturedError.new(
          error_class: e.class,
          error_message: e.message
        )
      end
      nil
    end
  end
end
