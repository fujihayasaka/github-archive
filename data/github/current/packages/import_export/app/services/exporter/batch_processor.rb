# typed: strict
# frozen_string_literal: true

module Exporter
  # Service to route batch processing based on batch type
  class BatchProcessor
    # Result object returned by processors containing processing outcomes
    class Result < T::Struct
      const :success_count, Integer
      const :failed_count, Integer
      const :errors, MigrationExportBatch::ModelProcessingErrors
      const :migration_file, T.nilable(MigrationFile)
      const :skipped, T::Boolean, default: false
    end

    sig { params(migration_export_batch: MigrationExportBatch, options: ExportOptions).void }
    def initialize(migration_export_batch:, options: ExportOptions.new)
      @migration_export_batch = migration_export_batch
      @options = options
    end

    sig { void }
    def process
      state_manager = BatchStateManager.new(
        migration_export_batch: @migration_export_batch
      )
      metrics_reporter = MetricsReporter.new(
        migration: T.must(@migration_export_batch.migration),
        migration_export_batch: @migration_export_batch
      )

      state_manager.start_batch

      begin
        result = route_to_processor(metrics_reporter)

        update_migration_file(T.must(result.migration_file), metrics_reporter) if result.migration_file

        state_manager.complete_batch(
          success_count: result.success_count,
          failed_count: result.failed_count,
          processing_errors: result.errors
        )

        metrics_reporter.report_success
        metrics_reporter.report_model_counts(
          success_count: result.success_count,
          failed_count: result.failed_count
        )
      rescue => error
        state_manager.requeue_batch(error: error)
        raise error
      end
    end

    private

    sig { params(metrics_reporter: MetricsReporter).returns(Result) }
    def route_to_processor(metrics_reporter)
      case @migration_export_batch.type.to_sym
      when :serialization
        temp_dir = Dir.mktmpdir("serialization_")
        begin
          process_serialization(metrics_reporter, temp_dir)
        ensure
          FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
        end
      when :archiving
        staging_path = GitHub.migration_file_staging_path
        FileUtils.mkdir_p(staging_path) unless File.exist?(staging_path)
        working_dir = Dir.mktmpdir("migration_export_batch_#{@migration_export_batch.id}_", staging_path)
        begin
          process_archiving(metrics_reporter, working_dir)
        ensure
          FileUtils.rm_rf(working_dir) if File.exist?(working_dir)
        end
      else
        raise ArgumentError, "Unknown batch type: #{@migration_export_batch.type}"
      end
    end

    sig { params(migration_file: MigrationFile, metrics_reporter: MetricsReporter).void }
    def update_migration_file(migration_file, metrics_reporter)
      ConnectionRetry.with_retry(
        migration: T.must(@migration_export_batch.migration),
        query_name: :update_migration_file,
        migration_export_batch: @migration_export_batch
      ) do
        ActiveRecord::Base.connected_to(role: :writing) do
          @migration_export_batch.update!(migration_file: migration_file)
        end
      end

      metrics_reporter.report_archive_size(migration_file.size)
    end

    sig { params(metrics_reporter: MetricsReporter, working_dir: String).returns(Result) }
    def process_serialization(metrics_reporter, working_dir)
      processor = BatchSerializationProcessor.new(
        migration_export_batch: @migration_export_batch,
        metrics_reporter: metrics_reporter,
        working_dir: working_dir,
        options: @options
      )
      processor.process
    end

    sig { params(metrics_reporter: MetricsReporter, working_dir: String).returns(Result) }
    def process_archiving(metrics_reporter, working_dir)
      processor = BatchArchiverProcessor.new(
        migration_export_batch: @migration_export_batch,
        metrics_reporter: metrics_reporter,
        working_dir: working_dir,
        options: @options
      )
      processor.process
    end
  end
end
