# typed: true
# frozen_string_literal: true

class IssueOrchestrationSweeperJob < ApplicationJob
  queue_as :issue_orchestration_sweeper
  retry_on_dirty_exit

  schedule interval: 5.minutes

  # Only one of these jobs should run at any given time.
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform
    with_write do
      IssueOrchestration.restart_stuck_orchestrations
      IssueOrchestration.purge_old_orchestrations

      IssueCommentOrchestration.restart_stuck_orchestrations
      IssueCommentOrchestration.purge_old_orchestrations
    end
  end
end
