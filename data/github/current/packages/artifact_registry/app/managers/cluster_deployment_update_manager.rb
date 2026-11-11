# typed: true
# frozen_string_literal: true

# Performs DB mutations for cluster deployment records: create, update, decommission.
# Used by the async job (SetClusterDeploymentRecordsJob) and can later replace the
# inline mutation logic in the sync API endpoint.
#
# The optional `skip_records_updated_after` parameter enables last-write-wins guards
# for async updates. Records updated at or after this time are skipped to avoid
# overwriting concurrent changes. When nil (sync path), no guard is applied.
class ClusterDeploymentUpdateManager
  class UpdateResult < T::Struct
    const :count, Integer
    const :records, T::Array[T::Hash[Symbol, T.untyped]]
    const :artifact_metadata_ids_to_delete, T::Array[Integer]
  end

  sig { params(org: Organization, skip_records_updated_after: T.nilable(Time)).void }
  def initialize(org, skip_records_updated_after: nil)
    @org = org
    @skip_records_updated_after = skip_records_updated_after
  end

  # Soft-deletes deployment records that are no longer in the desired state.
  # Returns the count of records actually decommissioned and affected artifact_metadata_ids.
  sig { params(records: T::Array[ArtifactDeploymentRecord]).returns({ count: Integer, artifact_metadata_ids: T::Array[Integer] }) }
  def decommission_records(records)
    return { count: 0, artifact_metadata_ids: [] } if records.empty?

    ids = records.map(&:id)
    # May slightly over-count when skip_records_updated_after skips some records,
    # but soft_delete_by_ids safely re-checks for active associations before deleting.
    # Avoids an extra query to determine which records were actually decommissioned.
    artifact_metadata_ids = records.map(&:artifact_metadata_id).compact

    now = Time.current
    scope = ArtifactDeploymentRecord.where(id: ids)
    scope = scope.where("updated_at < ?", @skip_records_updated_after) if @skip_records_updated_after
    count = scope.update_all(deleted_at: now, updated_at: now)

    { count: count, artifact_metadata_ids: artifact_metadata_ids }
  end

  # Creates new deployment records and their associated artifact metadata.
  # Returns an UpdateResult with count, serialized records, and no deletions.
  sig { params(templates: T::Array[DeploymentTemplate]).returns(UpdateResult) }
  def create_records(templates)
    return UpdateResult.new(count: 0, records: [], artifact_metadata_ids_to_delete: []) if templates.empty?

    now = Time.current
    all_digests, repository_ids = extract_digests_and_repo_ids(templates)

    existing_artifact_ids = ArtifactMetadata.fetch_all_artifact_ids_by_digest_and_repo_id(@org.id, all_digests, repository_ids)
    bulk_artifact_insert = templates.flat_map { |t| t.build_artifact_metadata_inserts(existing_artifact_ids, @org.id, now) }
    bulk_artifact_insert.uniq! { |row| [row[:repository_id], row[:digest]] }

    records = T.let([], T::Array[T.untyped])

    ArtifactMetadata.transaction do
      insert_artifact_metadata(bulk_artifact_insert)

      all_artifact_ids = if bulk_artifact_insert.any?
        ArtifactMetadata.fetch_active_ids_by_digest_and_repo_id(@org.id, all_digests, repository_ids)
      else
        existing_artifact_ids
      end
      templates.each { |t| t.assign_artifact_metadata_ids!(all_artifact_ids, @org.id) }

      bulk_deployment_insert = templates.flat_map(&:build_hashes_per_repo)
      bulk_deployment_insert.each_slice(BATCH_SIZE) do |batch|
        timestamped_batch = batch.map { |attrs| attrs.merge(created_at: now, updated_at: now) }
        ArtifactDeploymentRecord.insert_all(timestamped_batch)
      end

      deployment_names = bulk_deployment_insert.map { |entry| entry[:deployment_name] }.uniq
      cluster = bulk_deployment_insert.first&.dig(:cluster)
      logical_environment = bulk_deployment_insert.first&.dig(:logical_environment)
      physical_environment = bulk_deployment_insert.first&.dig(:physical_environment)

      deployment_records = ArtifactDeploymentRecord.where(
        owner_id: @org.id,
        deployment_name: deployment_names,
        cluster: cluster,
        logical_environment: logical_environment,
        physical_environment: physical_environment,
        deleted_at: nil,
      ).to_a

      insert_tags(templates, deployment_records, now)
      records = deployment_records.map(&:to_hash)
    end

    UpdateResult.new(count: records.size, records: records, artifact_metadata_ids_to_delete: [])
  end

  # Updates existing deployment records with new template data.
  # Returns an UpdateResult with count, serialized records, and orphaned artifact_metadata_ids.
  sig { params(templates: T::Array[DeploymentTemplate], current_records: T::Array[ArtifactDeploymentRecord]).returns(UpdateResult) }
  def update_records(templates, current_records)
    return UpdateResult.new(count: 0, records: [], artifact_metadata_ids_to_delete: []) if templates.empty?

    now = Time.current
    all_digests, repository_ids = extract_digests_and_repo_ids(templates)

    existing_artifact_ids = ArtifactMetadata.fetch_all_artifact_ids_by_digest_and_repo_id(@org.id, all_digests, repository_ids)
    bulk_artifact_insert = templates.flat_map { |t| t.build_artifact_metadata_inserts(existing_artifact_ids, @org.id, now) }

    current_records_by_name = current_records.index_by(&:deployment_name)

    record_ids = []
    updated_records = T.let([], T::Array[T.untyped])
    artifact_metadata_ids_to_delete = T.let([], T::Array[T.untyped])

    ArtifactMetadata.transaction do
      insert_artifact_metadata(bulk_artifact_insert)

      all_artifact_ids = if bulk_artifact_insert.any?
        ArtifactMetadata.fetch_active_ids_by_digest_and_repo_id(@org.id, all_digests, repository_ids)
      else
        existing_artifact_ids
      end
      templates.each { |t| t.assign_artifact_metadata_ids!(all_artifact_ids, @org.id) }

      bulk_upsert = templates.flat_map do |template|
        existing_record = current_records_by_name[template.deployment_name]
        next [] if existing_record.nil?
        # Skip records updated at or after the cutoff (last-write-wins guard)
        next [] if @skip_records_updated_after && existing_record.updated_at >= @skip_records_updated_after

        record_ids << existing_record.id
        template.build_hashes_per_repo.map { |h| h.merge(id: existing_record.id, updated_at: now) }
      end

      sorted_upsert = bulk_upsert.sort_by { |h| h[:id] }
      sorted_upsert.each_slice(BATCH_SIZE) do |batch|
        # rubocop:disable GitHub/UpsertAll
        ArtifactDeploymentRecord.upsert_all(batch)
        # rubocop:enable GitHub/UpsertAll
      end

      ArtifactDeploymentRecordTag.where(deployment_record_id: record_ids).delete_all
      insert_tags(templates, current_records.select { |r| record_ids.include?(r.id) }, now)

      updated_records = ArtifactDeploymentRecord.where(id: record_ids).map(&:to_hash)

      # Only consider metadata IDs from records we actually updated for orphan detection
      old_artifact_metadata_ids = Set.new(
        current_records.select { |r| record_ids.include?(r.id) }.map(&:artifact_metadata_id).compact
      )
      new_artifact_metadata_ids = Set.new(updated_records.map { |r| r[:artifact_metadata_id] }.compact)
      artifact_metadata_ids_to_delete = (old_artifact_metadata_ids - new_artifact_metadata_ids).to_a
    end

    UpdateResult.new(count: updated_records.size, records: updated_records, artifact_metadata_ids_to_delete: artifact_metadata_ids_to_delete)
  end

  private

  BATCH_SIZE = 100

  sig { params(templates: T::Array[DeploymentTemplate]).returns([T::Array[String], T::Array[Integer]]) }
  def extract_digests_and_repo_ids(templates)
    all_digests = Set.new
    repository_ids = Set.new
    templates.each do |template|
      all_digests << template.artifact_template.digest
      T.must(template.linkage.repo_and_attestation_ids).each { |entry| repository_ids << entry[:repository_id] }
    end
    [all_digests.to_a.compact, repository_ids.to_a.compact]
  end

  sig { params(bulk_insert: T::Array[T::Hash[T.untyped, T.untyped]]).void }
  def insert_artifact_metadata(bulk_insert)
    bulk_insert.each_slice(BATCH_SIZE) do |batch|
      ArtifactMetadata.insert_all(batch)
    end
  end

  sig { params(templates: T::Array[DeploymentTemplate], deployment_records: T::Array[ArtifactDeploymentRecord], now: Time).void }
  def insert_tags(templates, deployment_records, now)
    records_by_name = deployment_records.group_by(&:deployment_name)
    bulk_tag_insert = templates.flat_map do |template|
      records = records_by_name[template.deployment_name]
      next [] if records.nil? || records.empty?
      records.flat_map { |record| template.build_tag_inserts(record.id, now) }
    end
    return if bulk_tag_insert.empty?

    bulk_tag_insert.each_slice(BATCH_SIZE) do |batch|
      ArtifactDeploymentRecordTag.insert_all(batch)
    end
  end
end
