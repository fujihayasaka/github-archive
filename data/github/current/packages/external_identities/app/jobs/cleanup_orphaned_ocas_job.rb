# typed: true
# frozen_string_literal: true

# Cleanup job for orphaned Organization Credential Authorizations (OCAs).
# This job identifies and deletes OCAs that reference non-existent credentials.
# The job processes records in batches to avoid loading all OCAs into memory at once.
class CleanupOrphanedOcasJob < ApplicationJob
  include ChecksJobUtility

  queue_as :cleanup_orphaned_ocas_job

  BATCH_SIZE = 1_000

  # Ensure only one instance runs at a time to avoid duplicate work
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Exempt from tenant context since cleanup spans all tenants
  exempt_from_tenant_context_requirement

  def perform
    # Runs only during off-peak traffic times to reduce DB load
    return if peak_traffic_time?

    GitHub.logger.info("info.message" => "Starting cleanup_orphaned_ocas job")

    orphaned_ocas = 0

    # Process OCAs in batches
    Organization::CredentialAuthorization.preload(:credential).find_in_batches(batch_size: BATCH_SIZE) do |ocas|
      # Identify OCAs with nil credentials (orphaned records)
      orphaned_ids = ocas.select { |oca| oca.credential.nil? }.map(&:id)
      next if orphaned_ids.empty?

      # Delete orphaned records
      with_write do
        Organization::CredentialAuthorization.where(id: orphaned_ids).delete_all
      end

      orphaned_ocas += orphaned_ids.size
    end

    GitHub.logger.info(
      "info.message" => "Finished cleanup_orphaned_ocas job",
      "gh.orphaned_ocas_count" => orphaned_ocas
    )
  end
end
