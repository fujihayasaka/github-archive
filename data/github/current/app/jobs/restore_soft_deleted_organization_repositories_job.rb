# typed: true
# frozen_string_literal: true

class RestoreSoftDeletedOrganizationRepositoriesJob < ApplicationJob
  extend T::Sig

  queue_as :restore_soft_deleted_org_repos

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = 100

  # Perform required background tasks when a soft-delete organization is restored.
  # We take the unix_timestamp so that we can still find the repos in the event the
  # job retries and the soft_deleted_organization entry has already been removed.
  sig { params(id: Integer, unix_timestamp: Integer).void }
  def perform(id, unix_timestamp)
    return if unix_timestamp.zero?
    return unless org = Organization.find_by(id: id)

    # We only want to restore the repos that were removed at the time of the soft-delete
    org_soft_deleted_at = Time.at(unix_timestamp)
    repos = org.deleted_repositories.where("deleted_at >= ?", org_soft_deleted_at)
    repos.in_batches(of: BATCH_SIZE) do |batch|
      with_write { batch.each { |r| Repository.restore(r.id) } }
    end
  end
end
