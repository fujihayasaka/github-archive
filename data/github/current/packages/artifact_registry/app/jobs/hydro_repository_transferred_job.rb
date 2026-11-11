# typed: strict
# frozen_string_literal: true

class HydroRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  include GitHub::Memoizer
  include RepositoryHydroMessageJobTenantContext

  queue_as :hydro_artifact_metadata_repository_transferred
  retry_on_dirty_exit

  sig { void }
  def perform
    # Virtual Registry is not supported in GHES, so we should skip processing
    # The job is not configured to run on GHES. This is an extra safeguard.
    return if GitHub.enterprise?

    repository_id = message[:repository_id]
    old_owner_id = message.dig(:previous_owner, :id)
    new_owner_id = message.dig(:new_owner, :id)

    old_owner = User.find_by(id: old_owner_id)
    # only proceed if the old owner is an organization
    return unless old_owner&.organization?

    # check if new owner is a user or organization
    new_owner = User.find_by(id: new_owner_id)
    # because the Organization class inherits from User, User.find_by will return both users and orgs
    # so we need to check the type
    transferred_to_user = new_owner&.user?
    # if transferred to a user, then the records should be marked as deleted
    # artifact metadata does not support user ownership

    now = Time.current
    with_write do
      record_ids = update_artifact_metadata(old_owner_id, new_owner_id, repository_id, now, transferred_to_user)
      update_deployment_records(record_ids, now, new_owner_id, transferred_to_user) if record_ids.present?
      # update storage records
      update_storage_records(record_ids, now, transferred_to_user) if record_ids.present?
    end
  end

  protected

  sig { params(old_owner_id: Integer, new_owner_id: Integer, repository_id: Integer, current_time: Time, transferred_to_user: T::Boolean).returns(T::Array[Integer]) }
  def update_artifact_metadata(old_owner_id, new_owner_id, repository_id, current_time, transferred_to_user)
    updates = { owner_id: new_owner_id, attestation_id: nil, updated_at: current_time }
    if transferred_to_user
      updates[:deleted_at] = current_time
      updates[:status] = ArtifactMetadata.statuses[:deleted]
    end

    ids = ArtifactMetadata
      .where(owner_id: old_owner_id, repository_id: repository_id, deleted_at: nil)
      .pluck(:id)

    ArtifactMetadata.where(id: ids).update_all(updates)

    ids
  end

  sig { params(artifact_metadata_ids: T::Array[Integer], current_time: Time, new_owner_id: Integer, transferred_to_user: T::Boolean).void }
  def update_deployment_records(artifact_metadata_ids, current_time, new_owner_id, transferred_to_user)
    updates = { owner_id: new_owner_id, updated_at: current_time }
    if transferred_to_user
      updates[:deleted_at] = current_time
    end

    ArtifactDeploymentRecord
      .where(artifact_metadata_id: artifact_metadata_ids, deleted_at: nil)
      .update_all(updates)
  end

  sig { params(artifact_metadata_ids: T::Array[Integer], current_time: Time, transferred_to_user: T::Boolean).void }
  def update_storage_records(artifact_metadata_ids, current_time, transferred_to_user)
    return unless transferred_to_user

    ArtifactStorageRecord
      .where(artifact_metadata_id: artifact_metadata_ids, deleted_at: nil)
      .update_all(updated_at: current_time, deleted_at: current_time)
  end

  sig { override.returns(T::Hash[String, T.untyped]) }
  def logging_context
    super.merge({
      "gh.repo.owner.id.old": message.dig(:previous_owner, :id),
      "gh.repo.owner.id.new": message.dig(:new_owner, :id),
    })
  end
end
