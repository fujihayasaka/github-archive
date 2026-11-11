# typed: true
# frozen_string_literal: true

# Attempts to soft delete artifact metadata records in bulk by ID.
# Only artifacts without active deployment or storage record associations will be soft deleted.
# Used asynchronously by the /orgs/:org_id/artifacts/metadata/deployment-record/cluster/:cluster
# endpoint to soft delete artifacts associated with decommissioned deployment records at once.
class ArtifactMetadataBulkSoftDeleteJob < ApplicationJob
  queue_as :artifact_metadata_bulk_soft_delete

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  sig { params(artifact_metadata_ids: T::Array[Integer]).void }
  def perform(artifact_metadata_ids)
    GitHub.logger.info("Starting bulk soft delete of artifact metadata records", "artifact_metadata_ids_count" => artifact_metadata_ids.size)
    return if artifact_metadata_ids.empty?

    ArtifactMetadata.soft_delete_by_ids(artifact_metadata_ids)
  end
end
