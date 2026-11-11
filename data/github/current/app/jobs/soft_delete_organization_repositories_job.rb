# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SoftDeleteOrganizationRepositoriesJob < ApplicationJob
  queue_as :soft_delete_org_repos

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |id|
    org = Organization.soft_deleted.find_by(id: id)
    org&.business
  end

  BATCH_SIZE = 100

  # Perform required background tasks when an organization is soft-deleted.
  sig { params(id: Integer).void }
  def perform(id)
    return unless org = Organization.soft_deleted.find_by(id: id)

    deleter = User.find_by_login(org.deleted_by)
    org.repositories.in_batches(of: BATCH_SIZE) do |batch|
      with_write { batch.each { |repo| repo.remove(deleter) unless repo.deleted? } }
    end
  end
end
