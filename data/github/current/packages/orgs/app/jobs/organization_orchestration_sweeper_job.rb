# typed: true
# frozen_string_literal: true

class OrganizationOrchestrationSweeperJob < ApplicationJob
  queue_as :organization_orchestration_sweeper
  retry_on_dirty_exit

  schedule interval: 5.minutes

  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  PURGE_LIMIT = 100_000

  def perform
    with_write do
      OrganizationOrchestration.restart_stuck_orchestrations
      OrganizationOrchestration.purge_old_orchestrations(purge_limit: PURGE_LIMIT)
    end
  end
end
