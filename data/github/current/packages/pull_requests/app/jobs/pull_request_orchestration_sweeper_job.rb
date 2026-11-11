# typed: true
# frozen_string_literal: true

class PullRequestOrchestrationSweeperJob < ApplicationJob
  queue_as :pull_request_orchestration_sweeper
  retry_on_dirty_exit

  schedule interval: 5.minutes

  # Only one of these jobs should run at any given time.
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform
    with_write do
      PullRequestReviewCommentOrchestration.restart_stuck_orchestrations
      PullRequestReviewCommentOrchestration.purge_old_orchestrations

      if FeatureFlag.vexi.enabled?(:cotd_review_orchestration_sweepers, default: false)
        PullRequestReviewOrchestration.restart_stuck_orchestrations
        PullRequestReviewOrchestration.purge_old_orchestrations
      end

      PullRequestOrchestration.restart_stuck_orchestrations
      PullRequestOrchestration.purge_old_orchestrations
    end
  end
end
