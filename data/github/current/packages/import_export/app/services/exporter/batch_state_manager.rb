# typed: strict
# frozen_string_literal: true

module Exporter
  # BatchStateManager is responsible for managing state transitions of MigrationExportBatch objects
  # within the export workflow. It provides methods to claim, start, complete, fail, abort, and retry
  # batches, wrapping all state changes with retry and throttle logic to ensure robustness against
  # transient database or connection errors.
  #
  # This class is typically used by export jobs and services to safely update batch states:
  #   manager = Exporter::BatchStateManager.new(migration_export_batch: batch)
  #   manager.claim_batch!
  #   manager.start_batch
  #   manager.complete_batch(success_count: 10, failed_count: 2, processing_errors: {...})
  #   manager.fail_batch(error: exception)
  #   manager.abort_batch(reason: "Aborted by user")
  #   manager.mark_for_retry
  #
  # All state-changing methods are wrapped with retry and throttle logic to handle transient failures.
  class BatchStateManager
    MAX_RETRIES = 5

    sig { params(migration_export_batch: MigrationExportBatch).void }
    def initialize(migration_export_batch:)
      @migration_export_batch = migration_export_batch
    end

    sig { void }
    def claim_batch!
      with_retry do
        @migration_export_batch.claim!
      end
    end

    sig { void }
    def start_batch
      with_retry_and_throttle do
        MigrationExportBatch.transaction do
          @migration_export_batch.update!(
            started_at: Time.current,
            completed_at: nil,
            critical_error: nil,
            processing_errors: {},
            success_count: 0,
            failed_count: 0
          )
          @migration_export_batch.start!
        end
      end
    end

    sig do
      params(
        success_count: Integer,
        failed_count: Integer,
        processing_errors: T.nilable(MigrationExportBatch::ModelProcessingErrors)
      ).void
    end
    def complete_batch(success_count:, failed_count:, processing_errors: nil)
      with_retry_and_throttle do
        MigrationExportBatch.transaction do
          @migration_export_batch.update!(
            completed_at: Time.current,
            success_count: success_count,
            failed_count: failed_count,
            processing_errors: processing_errors.presence,
            critical_error: nil
          )

          # Use completed_with_failures state if there are any processing errors
          if processing_errors.present?
            @migration_export_batch.complete_with_failures!
          else
            @migration_export_batch.complete!
          end
        end
      end
    end

    sig do
      params(
        error: Exception
      ).void
    end
    def fail_batch(error:)
      with_retry_and_throttle do
        MigrationExportBatch.transaction do
          @migration_export_batch.update!(
            completed_at: Time.current,
            critical_error: MigrationExportBatch::CapturedError.new(
              error_class: error.class,
              error_message: error.message
            ),
            processing_errors: {},
            success_count: 0,
            failed_count: 0
          )

          @migration_export_batch.fail!
        end
      end
    end

    sig { params(reason: String).void }
    def abort_batch(reason:)
      with_retry_and_throttle do
        MigrationExportBatch.transaction do
          @migration_export_batch.update!(

            completed_at: Time.current,
            critical_error: MigrationExportBatch::CapturedError.new(
              error_class: StandardError,
              error_message: reason
            ),
            processing_errors: {},
            success_count: 0,
            failed_count: 0
          )
          @migration_export_batch.abort!
        end
      end
    end

    sig { void }
    def requeue_batch
      with_retry_and_throttle do
        @migration_export_batch.requeue!
      end
    end

    private

    sig do
      type_parameters(:T)
        .params(
          blk: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
    end
    def with_retry_and_throttle(&blk)
      ConnectionRetry.with_retry(
        migration: T.must(@migration_export_batch.migration),
        query_name: :batch_state_update,
        migration_export_batch: @migration_export_batch
      ) do
        MigrationExportBatch.throttle_with_retry(max_retry_count: MAX_RETRIES) do
          ActiveRecord::Base.connected_to(role: :writing, &blk)
        end
      end
    end

    sig do
      type_parameters(:T)
        .params(
          blk: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
    end
    def with_retry(&blk)
      ConnectionRetry.with_retry(
        migration: T.must(@migration_export_batch.migration),
        query_name: :batch_state_update,
        migration_export_batch: @migration_export_batch
      ) do
        ActiveRecord::Base.connected_to(role: :writing, &blk)
      end
    end
  end
end
