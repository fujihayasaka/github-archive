# typed: true
# frozen_string_literal: true

class SetArtifactProvenanceAttestationJob < BatchedJob
  queue_as :set_artifact_provenance_attestation_job

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  sig { params(metadata_records: T::Array[ArtifactMetadata], args: T.untyped, options: T.untyped).void }
  def process_batch(metadata_records, *args, **options)
    digests = metadata_records.map(&:digest)
    org_id = metadata_records.first&.owner_id
    org = Organization.find_by(id: org_id)
    if org.nil?
      GitHub.logger.error("Organization not found for org_id #{org_id}", "gh.org.id" => org_id)
      return
    end

    # Because only primitive types can be passed to ApplicationJob, we need to instantiate the metrics object here
    metrics = SetClusterBackgroundJobMetrics.new("SetArtifactProvenanceAttestationJob")
    attestation_identifiers = begin
      attestation_identifiers = ArtifactMetadataManager::fetch_validated_attestation_identifiers!(org, digests, metrics)
    rescue ArtifactMetadataManager::ErrTrustMetadata => e
      GitHub.logger.error("call to fetch attestations from TMA with org #{org_id} and digests #{digests.join(', ')} failed", "gh.org.id" => org.id, "gh.repo.attestation.subject_digests" => digests)
      # Re-raise the error so the job can retry
      raise e
    end

    if attestation_identifiers.blank?
      GitHub.logger.info("No attestation identifiers found by TMA", "gh.org.id" => org.id, "gh.repo.attestation.subject_digests" => digests)
      return
    end

    # Build an index to look up by digest and repository_id
    attestation_by_digest_and_repo = attestation_identifiers.transform_values do |identifiers|
      identifiers.index_by { |id| id[:repository_id] }
    end

    bulk_update_metadata = []
    ArtifactMetadata.throttle_writes do
      metadata_records.each do |md|
        # Because there can be multiple metadata records with the same digest but different repository_ids,
        # we need to look up the attestation identifier using both the digest and repository_id
        identifier_map = attestation_by_digest_and_repo[md.digest]
        next unless identifier_map
        current_attestation_id = md.attestation_id
        new_attestation_id = identifier_map[md.repository_id]&.dig(:attestation_id)
        md.update!(attestation_id: new_attestation_id) if current_attestation_id != new_attestation_id
      end
    end
  end

  sig { params(args: T.untyped, ids: T::Array[Integer], timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(T::Array[ArtifactMetadata]) }
  def next_batch(*args, ids:, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    ArtifactMetadata.where(id: ids).where("id > ?", offset_item_id).limit(BATCH_SIZE).order(id: :asc).to_a
  end
end
