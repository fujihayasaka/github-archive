# typed: strict
# frozen_string_literal: true

require "csv"

module Exporter
  # Service for generating audit log CSV file from failed export batches.
  #
  # This service processes batches in 'failed' or 'completed_with_failures' states
  # and creates a CSV file containing information about failed models.
  class GenerateBatchAuditLog
    BATCH_SIZE = 1000
    MAX_RETRIES = 5

    sig do
      params(
        migration: Migration,
        output_path: Pathname
      ).void
    end
    def initialize(migration:, output_path:)
      @migration = migration
      @output_path = output_path
      @model_url_service = T.let(GitHub::Migrator::ModelUrlService.new, GitHub::Migrator::ModelUrlService)
    end

    sig { void }
    def call
      failed_batches_for_migration do |failed_batches|
        return if failed_batches.empty?

        write_to_csv(failed_batches)
      end
    end

    private

    # Yields failed batches for the migration.
    #
    # Yields each batch as an ActiveRecord::Relation of MigrationExportBatch records.
    # Each MigrationExportBatch record has the following fields available:
    #   - id: Integer
    #   - migration_id: Integer
    #   - state: String (e.g., 'failed', 'completed_with_failures')
    #   - type: String (e.g., 'serialization')
    #   - created_at: DateTime
    #   - updated_at: DateTime
    # The block receives an ActiveRecord::Batches::BatchEnumerator, where each batch is a relation of MigrationExportBatch.
    sig { params(block: T.proc.params(arg0: T.untyped).void).void }
    def failed_batches_for_migration(&block)
      ConnectionRetry.with_retry(
        migration: @migration,
        query_name: :fetch_failed_batches
      ) do
        MigrationExportBatch.throttle_with_retry(max_retry_count: MAX_RETRIES) do
          failed_state = MigrationExportBatch.workflow_spec.states[:failed].value
          completed_with_failures_state = MigrationExportBatch.workflow_spec.states[:completed_with_failures].value

          MigrationExportBatch
            .where(migration_id: @migration.id)
            .where(state: [failed_state, completed_with_failures_state])
            .where(type: :serialization)
            .in_batches(of: BATCH_SIZE, &block)
        end
      end
    end

    # Fetches models by IDs and yields a hash indexed by ID.
    #
    # model_class - An ActiveRecord::Base subclass representing the model to fetch.
    # model_ids - Array of model IDs to fetch (Integer or String).
    #
    # Yields:
    #   models_by_id - Hash mapping model_id (Integer or String) to model instance (model_class).
    sig { params(model_class: T.untyped, model_ids: T.untyped, block: T.proc.params(arg0: T.untyped).void).void }
    def models_by_id_for_batch(model_class, model_ids, &block)
      ConnectionRetry.with_retry(
        migration: @migration,
        query_name: :fetch_models_by_id
      ) do
        model_class.throttle_with_retry(max_retry_count: MAX_RETRIES) do
          models = model_class.where(id: model_ids)
          models_by_id = models.index_by(&:id)

          yield models_by_id
        end
      end
    end

    # Writes batch failures to a csv file.
    #
    # failed_batches - ActiveRecord::Relation of MigrationExportBatch records with failures
    #
    # Returns nothing.
    sig { params(failed_batches: T.untyped).void }
    def write_to_csv(failed_batches)
      rows = []

      # Group batches by model_type
      batches_by_model_type = Hash.new { |h, k| h[k] = [] }
      failed_batches.find_each do |batch|
        batches_by_model_type[batch.model_type] << batch
      end

      # For each model_type, collect all needed model_ids and fetch models in one query
      models_by_type_and_id = {}
      batches_by_model_type.each do |model_type, batches|
        migratable_model = MigratableModelResolver.resolve(model_type)
        model_class = migratable_model.model_class

        # Collect all model_ids needed for this model_type
        all_model_ids = []
        batches.each do |batch|
          if batch.failed? && batch.critical_error
            all_model_ids.concat(batch.model_ids)
          end
          if batch.completed_with_failures? && batch.processing_errors.any?
            all_model_ids.concat(batch.processing_errors.keys)
          end
        end
        all_model_ids.uniq!

        # Fetch all models in one query and build a hash
        models = model_class.where(id: all_model_ids)
        models_by_id = models.index_by { |m| m.id }
        models_by_type_and_id[model_type] = models_by_id
      end

      # Now iterate over batches and use the pre-fetched models
      failed_batches.find_each do |batch|
        models_by_id = models_by_type_and_id[batch.model_type]

        # For batches in 'failed' state, write each model_id with the critical_error
        if batch.failed? && batch.critical_error
          batch.model_ids.each do |model_id|
            model = models_by_id[model_id]
            source_url = @model_url_service.url_for_model(model)

            rows << [
              batch.model_type,
              model_id,
              source_url,
              batch.current_state.name,
              batch.critical_error.error_message
            ]
          end
        end

        # For batches in 'completed_with_failures' state, write individual processing_errors
        if batch.completed_with_failures? && batch.processing_errors.any?
          batch.processing_errors.each do |model_id, error|
            model = models_by_id[model_id]
            source_url = @model_url_service.url_for_model(model)

            rows << [
              batch.model_type,
              model_id,
              source_url,
              batch.current_state.name,
              error.error_message
            ]
          end
        end
      end

      # Only create CSV file if there are actual errors to write
      return if rows.empty?

      CSV.open(@output_path, "w") do |csv|
        csv << %w[model_name model_id source_url state warning]
        rows.each { |row| csv << row }
      end
    end
  end
end
