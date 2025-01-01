# typed: true
# frozen_string_literal: true

class SoftDeleteOrganizationProjectsJob < ApplicationJob
  queue_as :soft_delete_org_projects

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = 100

  # Perform required background tasks when an organization is soft-deleted.
  sig { params(id: Integer).void }
  def perform(id)
    return unless org = Organization.soft_deleted.find_by(id: id)

    deleter = User.find_by_login(org.deleted_by)
    org.memex_projects.active_projects.in_batches(of: BATCH_SIZE) do |batch|
      with_write { batch.each { |project| project.soft_delete!(deleter) } }
    end
  end
end
