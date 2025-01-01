# typed: true
# frozen_string_literal: true

class DanglingIssueOrchestrationStarterJob < BatchedJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :dangling_issue_orchestration_starter

  # Tenant is resolved from repo during orchestration.execute
  # https://github.com/github/github/blob/master/packages/repositories/app/models/orchestration.rb#L295
  exempt_from_tenant_context_requirement

  BATCH_SIZE = 100.freeze

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  SCHEDULING_INTERVAL = 10.seconds.freeze
  LOCK_TIMEOUT = 2.minutes.freeze

  # don't run job on enterprise.
  schedule interval: SCHEDULING_INTERVAL, condition: -> { !GitHub.enterprise? }

  # Only one of these jobs should run at any given time.
  locked_by timeout: LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    return [] if abort_due_to_long_run?(timestamp)

    IssueOrchestration.dangling_orchestrations_batch(timestamp, offset_item_id, BATCH_SIZE)
  end

  def process_batch(batch, *args, **options)
    IssueOrchestration.start_dangling_orchestrations(batch)
  end

  def abort_due_to_long_run?(start_timestamp)
    # If the job has been running for more than lock timeout minus 10 seconds, abort it.
    Time.now.utc - start_timestamp > (LOCK_TIMEOUT - 10.seconds)
  end
end
