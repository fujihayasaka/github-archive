# typed: true
# frozen_string_literal: true

class RemoveStaleAuthenticatedDevicesJob < ApplicationJob
  queue_as :remove_stale_authenticated_devices
  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit
  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 1.day
  schedule interval: 5.minutes, condition: -> { GitHub.sign_in_analysis_enabled? }

  REMOVE_AFTER_DURATION = 12.months
  BATCH_SIZE = 100

  REMOVAL_CONDITIONS = <<-SQL
    accessed_at < :after
  SQL

  WITHOUT_ACCOUNT_RECOVERY_DEVICE_IDS = <<-SQL
    id NOT IN (:account_recovery_device_ids)
  SQL

  def perform
    loop do
      authenticated_devices = AuthenticatedDevice.where(REMOVAL_CONDITIONS, {
        after: REMOVE_AFTER_DURATION.ago,
      }).limit(BATCH_SIZE)

      if GitHub.flipper[:remove_account_recovery_devices_for_stale_authenticated_devices_job].enabled?
        account_recovery_device_ids = TwoFactorRecoveryRequest.where("authenticated_device_id IS NOT NULL").pluck(:authenticated_device_id)
        # If any of the account recovery requests are still active,
        # we don't want to remove the authenticated device associated with them
        authenticated_devices = authenticated_devices.where(WITHOUT_ACCOUNT_RECOVERY_DEVICE_IDS, {
          account_recovery_device_ids: account_recovery_device_ids
        }) if account_recovery_device_ids.present?
      end

      authenticated_devices = authenticated_devices.preload(:trusted_devices).to_a

      deleted_count = AuthenticatedDevice.throttle_with_retry(max_retry_count: 8) do
        ActiveRecord::Base.connected_to(role: :writing) do
          TrustedDeviceClientRegistration.where(authenticated_device: authenticated_devices).delete_all
          AuthenticatedDevice.where(id: authenticated_devices).delete_all
        end
      end
      GitHub.dogstats.count("authenticated_devices", deleted_count, tags: ["action:destroy", "reason:stale"])

      break if deleted_count < BATCH_SIZE
      # sleeping here arbitrarily for 15 seconds in hopes to give the deletes enough time to replicate before the next read
      # if this ends up not being enough time, and there is a high replication lag, the only consequence is a break on the loop - meaning the job will stop and will wait until the next job is scheduled (at most 5 minutes)
      sleep 15
    end
  end
end
