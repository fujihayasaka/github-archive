# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RestoreSoftDeletedOrganizationProjectsJob < ApplicationJob
  queue_as :restore_soft_deleted_org_projects

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |id|
    org = Organization.find_by(id: id)
    org&.business
  end

  BATCH_SIZE = 100

  # Perform required background tasks when a soft-delete organization is restored.
  # We take the unix_timestamp so that we can still find the projects in the event the
  # job retries and the soft_deleted_organization entry has already been removed.
  sig { params(id: Integer, unix_timestamp: Integer).void }
  def perform(id, unix_timestamp)
    return if unix_timestamp.zero?
    return unless org = Organization.find_by(id: id)

    # We only want to restore the projects that were removed at the time of the soft-delete
    org_soft_deleted_at = Time.zone.at(unix_timestamp)

    projects = org.memex_projects.deleted_projects.where("deleted_at >= ?", org_soft_deleted_at)
    projects.in_batches(of: BATCH_SIZE) do |batch|
      with_write { batch.each { |project| project.restore! } }
    end
  end
end
