# typed: true
# frozen_string_literal: true

class BusinessOrchestrationSweeperJob < ApplicationJob
  queue_as :business_orchestration_sweeper
  retry_on_dirty_exit

  schedule interval: 5.minutes

  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform
    with_write do
      BusinessOrchestration.restart_stuck_orchestrations
      BusinessOrchestration.purge_old_orchestrations
    end
  end
end
