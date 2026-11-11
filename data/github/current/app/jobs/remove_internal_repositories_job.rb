# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveInternalRepositoriesJob < ApplicationJob
  queue_as :remove_internal_repositories
  retry_on_dirty_exit

  BATCH_SIZE = 5000

  resolve_tenant_context do |organization|
    organization&.business
  end

  # Public: Remove all InternalRepository records for the org, without
  # destroying the associated Repository records.
  #
  # Note: This does not destroy the Repository records associated with the
  # InternalRepository records. This effectively converts the repositories
  # from internal to private.
  #
  # organization - target containing InternalRepository records
  #
  # Returns nothing.
  def perform(organization, actor: nil, offset_id: 0)
    @actor = actor
    batch = organization.repositories.limit(BATCH_SIZE).offset(offset_id).order(:id).pluck(:id)

    return if batch.empty?

    remove_internal_repositories(batch)

    # Queue another job if there are more repos to process
    unless batch.size < BATCH_SIZE
      RemoveInternalRepositoriesJob.perform_later(organization, actor: @actor, offset_id: offset_id + BATCH_SIZE)
    end
  end

  private

  def remove_internal_repositories(org_repo_ids)
    internal_repos = InternalRepository.where(repository_id: org_repo_ids)
    Repository.where(id: internal_repos.pluck(:repository_id)).each do |repo|
      repo.instrument :access, access: :private, visibility: :private, actor: @actor, previous_visibility: :internal
    end

    with_write { internal_repos.delete_all }
  end
end
