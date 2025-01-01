# typed: true
# frozen_string_literal: true

class RepositoryOrchestrationSweeperJob < ApplicationJob
  queue_as :repository_orchestration_sweeper
  retry_on_dirty_exit

  schedule interval: 5.minutes

  # Only one of these jobs should run at any given time.
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  PURGE_LIMIT = 100_000

  def perform
    with_write do
      RepositoryOrchestration.restart_stuck_orchestrations
      RepositoryOrchestration.purge_old_orchestrations(purge_limit: PURGE_LIMIT)
    end
  end
end
