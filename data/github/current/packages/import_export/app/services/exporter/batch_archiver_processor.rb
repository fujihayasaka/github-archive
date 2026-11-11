# typed: strict
# frozen_string_literal: true

module Exporter
  # BatchArchiverProcessor handles archiving of models to the filesystem
  # during the export process. It builds the archiver, saves models,
  # creates an archive, and uploads it to cloud storage.
  class BatchArchiverProcessor
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

      # Track results (will be assigned from BatchArchiver result)
      success_count = T.let(0, Integer)
      failed_count = T.let(0, Integer)
      archiving_errors = T.let({}, MigrationExportBatch::ModelProcessingErrors)
      migration_file = T.let(nil, T.nilable(MigrationFile))

      begin
        @metrics_reporter.with_duration(operation: :archive_batch) do
          # Get actor and owner from migration
          migration = T.must(@migration_export_batch.migration)
          actor = T.must(migration.creator)
          owner = T.must(migration.owner)

          # Look up migratable model from registry
          migratable_model = MigratableModelResolver.resolve(model_type)

          # Build archiver for this model type
          archiver = migratable_model.build_archiver(
            actor: actor,
            migration_path: @working_dir
          )

          # Check if archiving should be skipped
          if should_skip_archiving?(archiver, model_type)
            return BatchProcessor::Result.new(
              success_count: 0,
              failed_count: 0,
              errors: {},
              migration_file: nil,
              skipped: true
            )
          end

          # Archive models using BatchArchiver
          @metrics_reporter.with_duration(operation: :archive_models) do
            batch_archiver = BatchArchiver.new(
              model_ids: model_ids,
              model_class: migratable_model.model_class,
              archiver: archiver,
              migration_export_batch: @migration_export_batch
            )
            result = batch_archiver.archive

            success_count = result.success_count
            failed_count = result.failed_count
            archiving_errors = result.archiving_errors
          end

          # Report archiving_errors
          @metrics_reporter.report_processing_errors(archiving_errors)

          # Create archive from working directory
          archive_path = @metrics_reporter.with_duration(operation: :create_archive) do
            create_archive(@working_dir)
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
        errors: archiving_errors,
        migration_file: migration_file,
        skipped: false
      )
    end

    private

    sig { params(archiver: T.nilable(GitHub::Migrator::BaseArchiver), model_type: String).returns(T::Boolean) }
    def should_skip_archiving?(archiver, model_type)
      # Skip if no archiver exists for this model type
      return true if archiver.nil?

      # Skip archiving if org_metadata_only is enabled
      return true if @options.org_metadata_only

      # Skip archiving repositories if exclude_git_data is enabled
      return true if model_type == "repository" && @options.exclude_git_data

      false
    end

    sig { params(file_directory: String).returns(String) }
    def create_archive(file_directory)
      archive_path = File.join(file_directory, "batch_#{@migration_export_batch.id}.tar.gz")
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
