# typed: strict
# frozen_string_literal: true

module Exporter
  class BatchSerializationProcessor
    sig do
      params(
        migration_export_batch: MigrationExportBatch,
        metrics_reporter: MetricsReporter,
        working_dir: String,
        options: ExportOptions
      ).void
    end
    def initialize(migration_export_batch:, metrics_reporter:, working_dir:, options: ExportOptions.new)
      @migration_export_batch = migration_export_batch
      @working_dir = working_dir
      @options = options
      @metrics_reporter = T.let(metrics_reporter, MetricsReporter)
    end

    sig { returns(BatchProcessor::Result) }
    def process
      # Get model type and IDs from batch record
      model_type = @migration_export_batch.model_type
      model_ids = @migration_export_batch.model_ids

      # Track results for rescue block
      success_count = T.let(0, Integer)
      failed_count = T.let(0, Integer)
      serialization_errors = T.let({}, MigrationExportBatch::ModelProcessingErrors)
      migration_file = T.let(nil, T.nilable(MigrationFile))

      begin
        @metrics_reporter.with_duration(operation: :serialize_batch) do
          # Get actor and owner from migration
          migration = T.must(@migration_export_batch.migration)
          actor = T.must(migration.creator)
          owner = T.must(migration.owner)

          # Look up migratable model from registry
          migratable_model = MigratableModelResolver.resolve(model_type)

          # Initialize serializer
          serializer = SerializerFactory.create(
            migratable_model: migratable_model,
            actor: actor,
            owner: owner,
            options: @options,
            migration_guid: migration.guid
          )

          # Initialize batch serializer and serialize all models
          model_class = migratable_model.model_class
          batch_serializer = BatchSerializer.new(
            model_ids: model_ids,
            serializer: serializer,
            working_dir: @working_dir,
            model_class: model_class,
            migration_export_batch: @migration_export_batch
          )

          # Serialize all models and track results
          results = @metrics_reporter.with_duration(operation: :serialize_models) do
            batch_serializer.serialize
          end

          success_count = results.success_count
          failed_count = results.failed_count
          serialization_errors = results.serialization_errors

          # Report serialization metrics
          @metrics_reporter.report_processing_errors(serialization_errors)

          # Create archive from working directory
          archive_path = @metrics_reporter.with_duration(operation: :create_archive) do
            create_archive
          end

          # Upload archive to cloud storage
          @metrics_reporter.with_duration(operation: :upload_archive) do
            migration_file = upload_archive(archive_path)
          end

          # Clean up the archive file after upload
          File.delete(archive_path) if File.exist?(archive_path)
        end
      end

      BatchProcessor::Result.new(
        success_count: success_count,
        failed_count: failed_count,
        errors: serialization_errors,
        migration_file: migration_file
      )
    end

    private

    sig { returns(String) }
    def create_archive
      archive_path = File.join(Dir.tmpdir, "batch_#{@migration_export_batch.id}.tar.gz")
      archiver = ArchiveCreator.new(
        working_dir: @working_dir,
        archive_path: archive_path
      )
      archiver.create
    end

    sig { params(archive_path: String).returns(MigrationFile) }
    def upload_archive(archive_path)
      migration = T.must(@migration_export_batch.migration)
      filename = "batch_#{@migration_export_batch.id}.tar.gz"

      uploader = FileUploader.new(
        migration: migration,
        archive_path: archive_path,
        filename: filename,
        content_type: "application/gzip"
      )

      uploader.upload
    end
  end
end
