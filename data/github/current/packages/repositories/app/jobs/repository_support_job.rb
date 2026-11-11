# typed: true
# frozen_string_literal: true

class RepositorySupportJob < ApplicationJob
  queue_as :repository_support
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Borrow the retryable exceptions from the orchestrations
  # This job is idempotent, so we can retry on any error (ideally to avoid incorrect RefPush data)
  retry_on *Orchestration::RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 2

  use_primaries ApplicationRecord::Repositories

  # Ensure the job only runs once per network at a time
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform(network_id: nil)
    if network_id
      Repositories::Support.fix_network(id: network_id)
    end
  end
end
