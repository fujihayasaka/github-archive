# typed: true
# frozen_string_literal: true

class CleanupExpiredPermissionsJob < BatchedJob
  queue_as :cleanup_expired_permissions

  LOCK_KEY = "cleanup_expired_permissions"

  schedule interval: 6.hours

  # Ensure only one of these jobs is in the queue or being worked at a time.
  locked_by key: ->(_job) { LOCK_KEY }, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  # This job is exempt from the tenant context requirement because it is
  # used to clean up expired `permissions` records regardless of the tenant.
  exempt_from_tenant_context_requirement

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    Permissions::Service.expired_permission_ids_with_limit_and_offset(timestamp:, offset_id: offset_item_id, limit: BATCH_SIZE)
  end

  def process_batch(batch, *args, **options)
    entry_point = Permissions::Service::EntryPoint.lookup(:cleanup_expired_permissions_job)
    Permissions::Service.revoke_permissions_by_id(batch, entry_point: entry_point)
  end

  def finalize_batch(batch, *args, progress:, **options)
    clear_lock
  end

  def next_batch_offset_item_id(batch, *args, **options)
    batch.max
  end

  private

  def perform(*args, initial_start: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    return unless FeatureFlag.vexi.enabled?(:run_cleanup_expired_permissions_job, default: false)

    super
  end
end
