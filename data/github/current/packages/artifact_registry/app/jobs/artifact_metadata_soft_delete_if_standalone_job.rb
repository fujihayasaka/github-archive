# typed: strict
# frozen_string_literal: true

# Checks whether a single artifact metadata record is standalone
# (no active deployment or storage records) and soft deletes it if so.
# Replaces the synchronous after_commit check that was previously performed
# inline on the web request path, avoiding killed queries under load.
class ArtifactMetadataSoftDeleteIfStandaloneJob < ApplicationJob
  queue_as :artifact_metadata_bulk_soft_delete

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  sig { params(artifact_metadata_id: Integer).void }
  def perform(artifact_metadata_id)
    metadata = ArtifactMetadata.find_by(id: artifact_metadata_id)
    return unless metadata

    ArtifactMetadata.throttle_writes do
      metadata.soft_delete_if_standalone
    end
  end
end
