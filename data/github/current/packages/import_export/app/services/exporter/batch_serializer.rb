# typed: strict
# frozen_string_literal: true

module Exporter
  class BatchSerializer
    class SerializationNullData < StandardError; end

    # Result object returned by serializer
    class Result < T::Struct
      const :success_count, Integer
      const :failed_count, Integer
      const :serialization_errors, MigrationExportBatch::ModelProcessingErrors
      const :found_ids, T::Set[Integer]
    end

    # Batch size for loading models from database
    BATCH_SIZE = 1000

    MAX_RETRIES = 5

    sig do
      params(
        model_ids: T::Array[Integer],
        serializer: GitHub::Migrator::BaseSerializer,
        working_dir: String,
        model_class: T.class_of(ApplicationRecord::Base),
        migration_export_batch: MigrationExportBatch
      ).void
    end
    def initialize(model_ids:, serializer:, working_dir:, model_class:, migration_export_batch:)
      @model_ids = model_ids
      @serializer = serializer
      @model_class = model_class
      @migration_export_batch = migration_export_batch
      @working_dir = working_dir
      model_type = T.must(model_class.name).underscore
      @scope_service = T.let(
        SerializerScope.new(serializer: serializer, model_type: model_type),
        SerializerScope
      )
    end

    sig { returns(Result) }
    def serialize
      success_count = 0
      failed_count = 0
      serialization_errors = T.let({}, MigrationExportBatch::ModelProcessingErrors)
      found_ids = Set.new

      @model_ids.each_slice(BATCH_SIZE).each_with_index do |id_batch, batch_index|
        models = load_batch(id_batch, serialization_errors, found_ids)
        unless models
          failed_count += id_batch.size
          next
        end

        # Create file writer for this batch
        file_writer = create_file_writer(batch_index)

        # Serialize and write each model individually
        models.each do |model|
          found_ids.add(model.id)

          begin
            serialized_model = @serializer.serialize(model)

            if serialized_model.nil?
              serialization_errors[model.id] = MigrationExportBatch::CapturedError.new(
                error_class: SerializationNullData,
                error_message: "Serialization returned nil",
                customer_message: customer_message_for(model)
              )
              failed_count += 1
            else
              # Write model to file immediately after serialization
              file_writer.write(serialized_model)
              success_count += 1
            end
          rescue StandardError => serialization_error
            # Capture all serialization errors and continue processing
            serialization_errors[model.id] = MigrationExportBatch::CapturedError.new(
              error_class: serialization_error.class,
              error_message: serialization_error.message,
              customer_message: customer_message_for(model)
            )
            failed_count += 1

            GitHub.logger.warn("Failed to serialize model", model_id: model.id, error: serialization_error.message)
          end
        end

        # Finalize the file writer to ensure all pending data is written
        file_writer.finalize
      end

      # Count missing models (IDs that were requested but not found)
      missing_ids = @model_ids - found_ids.to_a
      failed_count += missing_ids.size

      Result.new(
        success_count: success_count,
        failed_count: failed_count,
        serialization_errors: serialization_errors,
        found_ids: found_ids
      )
    end

    private

    # Creates a file writer with the appropriate prefix for the given batch index.
    # Prefix format: <model_type>_<batch_id>_<index>
    # Example: "users_1234567890123456789_00"
    sig { params(batch_index: Integer).returns(ModelFileWriter) }
    def create_file_writer(batch_index)
      model_type = @migration_export_batch.model_type.to_s.underscore
      batch_id = @migration_export_batch.id.to_s.rjust(19, "0")
      index = batch_index.to_s.rjust(2, "0")
      prefix = "#{model_type}_#{batch_id}_#{index}"

      ModelFileWriter.new(working_dir: @working_dir, prefix: prefix)
    end

    sig do
      params(
        id_batch: T::Array[Integer],
        serialization_errors: MigrationExportBatch::ModelProcessingErrors,
        found_ids: T::Set[Integer]
      ).returns(T.nilable(T::Array[ApplicationRecord::Base]))
    end
    def load_batch(id_batch, serialization_errors, found_ids)
      ConnectionRetry.with_retry(
        migration: T.must(@migration_export_batch.migration),
        query_name: :load_serialization_batch,
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
        serialization_errors[id] = MigrationExportBatch::CapturedError.new(
          error_class: e.class,
          error_message: e.message
        )
        found_ids.add(id) # Mark as "found" (even though failed) to avoid double-counting
      end
      nil
    end

    sig { params(model: ApplicationRecord::Base).returns(String) }
    def customer_message_for(model)
      critical_validation_errors = @serializer.critical_validation_errors(model)

      if critical_validation_errors.any?
        "Model could not be serialized due to validation errors: #{critical_validation_errors.full_messages.to_sentence}"
      else
        "Model could not be serialized due to serialization errors"
      end
    end
  end
end
