# typed: true
# frozen_string_literal: true

class DeleteExpiredReservedLoginTombstonesJob < ApplicationJob
  queue_as :delete_expired_reserved_login_tombstones
  retry_on_dirty_exit

  # Only one of these jobs should run at any given time.
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  schedule interval: 4.hours

  exempt_from_tenant_context_requirement

  def perform
    with_write { ReservedLogin.delete_expired_tombstones }
  end
end
