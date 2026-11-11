# typed: strict
# frozen_string_literal: true

class HydroRepositoryPurgedJob < Repositories::RepositoryHydroMessageJob
  include RepositoryHydroMessageJobTenantContext

  BATCH_SIZE = 100

  queue_as :hydro_artifact_metadata_repository_purged
  retry_on_dirty_exit

  sig { void }
  def perform
    # Virtual Registry is not supported in GHES, so we should skip processing
    # The job is not configured to run on GHES. This is an extra safeguard.
    return if GitHub.enterprise?

    now = Time.current
    with_write do
      artifact_metadata_ids = mark_artifact_metadata_deleted(repository_id, now)
      return if artifact_metadata_ids.empty?

      deployment_record_ids = decommission_deployment_records(artifact_metadata_ids, now)
      storage_record_ids = decommission_storage_records(artifact_metadata_ids, now)

      emit_decommissioned_record_events(deployment_record_ids, storage_record_ids)
    end
  end

  protected

  sig { params(repository_id: Integer, current_time: Time).returns(T::Array[Integer]) }
  def mark_artifact_metadata_deleted(repository_id, current_time)
    ids = ArtifactMetadata
      .where(repository_id: repository_id, deleted_at: nil)
      .pluck(:id)

    ids.each_slice(BATCH_SIZE) do |batch_ids|
      ArtifactMetadata.throttle_writes do
        ArtifactMetadata.where(id: batch_ids).update_all(
          status: ArtifactMetadata.statuses[:deleted],
          deleted_at: current_time,
          updated_at: current_time
        )
      end
    end

    ids
  end

  sig { params(artifact_metadata_ids: T::Array[Integer], current_time: Time).returns(T::Array[Integer]) }
  def decommission_deployment_records(artifact_metadata_ids, current_time)
    ids = ArtifactDeploymentRecord
      .where(artifact_metadata_id: artifact_metadata_ids, deleted_at: nil)
      .pluck(:id)

    ids.each_slice(BATCH_SIZE) do |batch_ids|
      ArtifactDeploymentRecord.throttle_writes do
        ArtifactDeploymentRecord.where(id: batch_ids).update_all(deleted_at: current_time, updated_at: current_time)
      end
    end

    ids
  end

  sig { params(artifact_metadata_ids: T::Array[Integer], current_time: Time).returns(T::Array[Integer]) }
  def decommission_storage_records(artifact_metadata_ids, current_time)
    ids = ArtifactStorageRecord
      .where(artifact_metadata_id: artifact_metadata_ids, deleted_at: nil)
      .pluck(:id)

    ids.each_slice(BATCH_SIZE) do |batch_ids|
      ArtifactStorageRecord.throttle_writes do
        ArtifactStorageRecord.where(id: batch_ids).update_all(deleted_at: current_time, updated_at: current_time)
      end
    end

    ids
  end

  sig { params(deployment_record_ids: T::Array[Integer], storage_record_ids: T::Array[Integer]).void }
  def emit_decommissioned_record_events(deployment_record_ids, storage_record_ids)
    deployment_records = ArtifactDeploymentRecord
      .includes(:artifact_metadata)
      .where(id: deployment_record_ids)

    deployment_records.find_each do |record|
      ArtifactRegistryHydroMessageManager.send_delete_hydro_message_for_deployment_record(record.to_hash)
    end

    storage_records = ArtifactStorageRecord
      .includes(:artifact_metadata)
      .where(id: storage_record_ids)

    storage_records.find_each do |record|
      ArtifactRegistryHydroMessageManager.send_delete_hydro_message_for_storage_record(record.to_hash)
    end
  end
end
