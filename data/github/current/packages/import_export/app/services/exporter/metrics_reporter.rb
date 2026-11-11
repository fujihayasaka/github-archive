# typed: strict
# frozen_string_literal: true

module Exporter
  class MetricsReporter

    sig { params(migration: Migration, migration_export_batch: T.nilable(MigrationExportBatch)).void }
    def initialize(migration:, migration_export_batch: nil)
      @migration = migration
      @migration_export_batch = migration_export_batch
    end

    sig { void }
    def report_success
      send_metric("gh.migration_tools.exporter.batch.success", [])
    end

    sig { void }
    def report_failure
      send_metric("gh.migration_tools.exporter.batch.failure", [])
    end

    sig { params(operation: Symbol, blk: T.proc.returns(T.untyped)).returns(T.untyped) }
    def with_duration(operation:, &blk)
      start_time = Time.now
      result = blk.call
      duration_ms = ((Time.now - start_time) * 1000).to_f.round(2)
      tags = base_tags + ["operation:#{operation}"]
      GitHub.dogstats.histogram("gh.migration_tools.exporter.batch.duration", duration_ms, tags: tags)
      result
    end


    sig { params(success_count: Integer, failed_count: Integer).void }
    def report_model_counts(success_count:, failed_count:)
      # Emit counters for aggregate totals across all batches
      GitHub.dogstats.count(
        "gh.migration_tools.exporter.models.success.total",
        success_count,
        tags: base_tags
      )

      GitHub.dogstats.count(
        "gh.migration_tools.exporter.models.failed.total",
        failed_count,
        tags: base_tags
      )
    end

    sig { params(size_bytes: Integer).void }
    def report_archive_size(size_bytes)
      GitHub.dogstats.gauge(
        "gh.migration_tools.exporter.batch.archive.size",
        size_bytes,
        tags: base_tags
      )
    end

    sig { params(errors: MigrationExportBatch::ModelProcessingErrors).void }
    def report_processing_errors(errors)
      errors.each do |_model_id, error|
        tag = "error_class:#{error.error_class}"
        send_metric("gh.migration_tools.exporter.batch.processing_errors", [tag])
      end
    end

    sig { params(query_name: Symbol, error_class: String).void }
    def report_connection_retry_exhausted(query_name:, error_class:)
      send_metric(
        "gh.migration_tools.exporter.connection_retry.exhausted",
        ["query_name:#{query_name}", "error_class:#{error_class}"]
      )
    end

    sig { params(model_type: String).void }
    def report_model_added(model_type:)
      send_metric(
        "gh.migration_tools.exporter.models.added",
        ["model_type:#{model_type}"]
      )
    end

    sig { params(model_type: String, batch_type: Symbol).void }
    def report_batch_queued(model_type:, batch_type:)
      send_metric(
        "gh.migration_tools.exporter.batch.queued",
        ["model_type:#{model_type}", "batch_type:#{batch_type}"]
      )
    end

    sig { params(model_type: String, error_message: String).void }
    def report_non_migratable_model(model_type:, error_message:)
      send_metric(
        "gh.migration_tools.exporter.models.non_migratable",
        ["model_type:#{model_type}", "error:#{error_message}"]
      )
    end

    private

    sig { params(metric: String, tags: T::Array[String]).void }
    def send_metric(metric, tags)
      full_tags = base_tags + tags
      GitHub.dogstats.increment(metric, tags: full_tags)
    end

    sig { returns(T::Array[String]) }
    def base_tags
      owner_id = @migration.owner_id
      creator_id = @migration.creator_id

      tags = [
        "owner_id:#{owner_id}",
        "creator_id:#{creator_id}"
      ]

      if @migration_export_batch
        model_type = @migration_export_batch.model_type
        batch_state = @migration_export_batch.current_state.name
        batch_type = @migration_export_batch.type

        tags += [
          "model_type:#{model_type}",
          "batch_state:#{batch_state}",
          "batch_type:#{batch_type}"
        ]
      end

      tags
    end
  end
end
