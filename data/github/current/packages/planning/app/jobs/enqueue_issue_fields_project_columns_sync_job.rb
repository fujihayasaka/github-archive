# typed: strict
# frozen_string_literal: true

# This job runs daily to enqueue individual SyncIssueFieldToProjectColumnsJob jobs
# for each unique IssueField that is referenced in a MemexProject.
#
# The job iterates over distinct issue_field_id values in the memex_project_columns
# table and enqueues a separate sync job for each one, allowing those jobs to
# ensure project columns stay in sync with their corresponding issue fields.
#
# The job leverages the `BatchedJob` framework to handle large datasets efficiently.
class EnqueueIssueFieldsProjectColumnsSyncJob < BatchedJob
  BATCH_SIZE = 1_000

  queue_as :enqueue_issue_fields_project_columns_sync

  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  schedule interval: 1.day

  retry_on WaitForReplication::DataUnavailable

  retry_on_dirty_exit

  retry_on_recoverable_exceptions

  around_enqueue do |_job, block|
    next unless job_enabled?
    block.call
  end

  sig do
    override
      .params(
        args: T.untyped,
        offset_item_id: Integer,
        _options: T.untyped
      )
      .returns(T::Array[Integer])
  end
  def next_batch(*args, offset_item_id: 0, **_options)
    MemexProjectColumn
      .where("issue_field_id > ?", offset_item_id)
      .order(issue_field_id: :asc)
      .limit(BATCH_SIZE)
      .distinct
      .pluck(:issue_field_id)
  end

  sig { override.params(batch: T::Array[Integer], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    SyncIssueFieldToProjectColumnsJob.sync_later(batch)
  end

  sig { override.params(batch: T::Array[Integer], args: T.untyped, options: T.untyped).returns(Integer) }
  def next_batch_offset_item_id(batch, *args, **options)
    T.must(batch.max)
  end

  private

  sig { returns(T::Boolean) }
  def job_enabled?
    !FeatureFlag.vexi.enabled?(:enqueue_issue_fields_project_columns_sync_job_disabled, default: false)
  end
end
