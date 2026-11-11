# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MarkArtifactMetadataRecordsDeletedForPurgedRepositories < Base
      class ArtifactMetadataModel < ApplicationRecord::ArtifactRegistry
        self.table_name = :artifact_metadata
        self.inheritance_column = :_type_disabled
      end

      class RepositoryModel < ApplicationRecord::Repositories
        self.table_name = :repositories
      end

      class ArtifactDeploymentRecordModel < ApplicationRecord::ArtifactRegistry
        self.table_name = :artifact_deployment_records

        sig { returns(Integer) }
        def artifact_metadata_id
          T.cast(self[:artifact_metadata_id], Integer)
        end
      end

      class ArtifactStorageRecordModel < ApplicationRecord::ArtifactRegistry
        self.table_name = :artifact_storage_records

        sig { returns(Integer) }
        def artifact_metadata_id
          T.cast(self[:artifact_metadata_id], Integer)
        end
      end

      class ArtifactMetadataDetails < T::Struct
        const :digest, T.nilable(String)
        const :owner_id, T.nilable(Integer)
        const :repository_id, T.nilable(Integer)
        const :attestation_id, T.nilable(Integer)
      end

      iterate_over :database_table, params: {
        model_class: ArtifactMetadataModel,
        conditions: "deleted_at IS NULL AND repository_id IS NOT NULL",
        columns: %i[id repository_id owner_id digest attestation_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        return if GitHub.enterprise?

        repository_ids = items.values.map { |row| row[:repository_id] }.compact.uniq
        return if repository_ids.empty?

        existing_repository_ids = RepositoryModel.where(id: repository_ids).pluck(:id).to_set
        metadata_ids_to_delete = T.let(items.filter_map do |metadata_id, row|
          next if existing_repository_ids.include?(row[:repository_id])

          Integer(metadata_id)
        end, T::Array[Integer])
        metadata_details_by_id = metadata_details_by_id_for(items, metadata_ids_to_delete)

        return if metadata_ids_to_delete.empty?

        if dry_run?
          log "Dry run: would mark #{metadata_ids_to_delete.size} artifact metadata records deleted for purged repositories"
          return
        end

        log "Attempting to mark #{metadata_ids_to_delete.size} artifact metadata records deleted for purged repositories"
        current_time = Time.current
        deployment_record_ids = mark_deployment_records_deleted(metadata_ids_to_delete, current_time)
        storage_record_ids = mark_storage_records_deleted(metadata_ids_to_delete, current_time)
        mark_artifact_metadata_deleted(metadata_ids_to_delete, current_time)
        emit_decommissioned_record_events(deployment_record_ids, storage_record_ids, metadata_details_by_id)

        log "Marked #{metadata_ids_to_delete.size} artifact metadata records deleted for purged repositories"
      end

      private

      sig { params(metadata_ids: T::Array[Integer], current_time: Time).returns(T::Array[Integer]) }
      def mark_deployment_records_deleted(metadata_ids, current_time)
        # Collect all record IDs first, then batch the updates
        all_record_ids = T.let([], T::Array[Integer])

        metadata_ids.each_slice(500) do |batch_ids|
          batch_record_ids = ArtifactDeploymentRecordModel
            .where(artifact_metadata_id: batch_ids, deleted_at: nil)
            .pluck(:id)

          all_record_ids.concat(batch_record_ids)
        end

        return [] if all_record_ids.empty?

        # Batch the actual record updates
        all_record_ids.each_slice(500) do |batch_ids|
          write_to(model_class: ArtifactDeploymentRecordModel) do
            ArtifactDeploymentRecordModel
              .where(id: batch_ids)
              .update_all(deleted_at: current_time, updated_at: current_time)
          end
        end

        all_record_ids
      end

      sig { params(metadata_ids: T::Array[Integer], current_time: Time).returns(T::Array[Integer]) }
      def mark_storage_records_deleted(metadata_ids, current_time)
        # Collect all record IDs first, then batch the updates
        all_record_ids = T.let([], T::Array[Integer])

        metadata_ids.each_slice(500) do |batch_ids|
          batch_record_ids = ArtifactStorageRecordModel
            .where(artifact_metadata_id: batch_ids, deleted_at: nil)
            .pluck(:id)

          all_record_ids.concat(batch_record_ids)
        end

        return [] if all_record_ids.empty?

        # Batch the actual record updates
        all_record_ids.each_slice(500) do |batch_ids|
          write_to(model_class: ArtifactStorageRecordModel) do
            ArtifactStorageRecordModel
              .where(id: batch_ids)
              .update_all(deleted_at: current_time, updated_at: current_time)
          end
        end

        all_record_ids
      end

      sig { params(metadata_ids: T::Array[Integer], current_time: Time).void }
      def mark_artifact_metadata_deleted(metadata_ids, current_time)
        metadata_ids.each_slice(500) do |batch_ids|
          write_to(model_class: ArtifactMetadataModel) do
            ArtifactMetadataModel
              .where(id: batch_ids, deleted_at: nil)
              .update_all(
                deleted_at: current_time,
                status: ArtifactMetadata.statuses[:deleted],
                updated_at: current_time
              )
          end
        end
      end

      sig do
        params(
          deployment_record_ids: T::Array[Integer],
          storage_record_ids: T::Array[Integer],
          metadata_details_by_id: T::Hash[Integer, ArtifactMetadataDetails]
        ).void
      end
      def emit_decommissioned_record_events(deployment_record_ids, storage_record_ids, metadata_details_by_id)
        deployment_record_ids.each_slice(500) do |batch_ids|
          deployment_records = ArtifactDeploymentRecordModel.where(id: batch_ids).to_a

          deployment_records.each do |record|
            metadata = metadata_details_by_id[record.artifact_metadata_id]

            ArtifactRegistryHydroMessageManager.send_delete_hydro_message_for_deployment_record({
              id: record.id,
              digest: metadata&.digest,
              logical_environment: record.logical_environment,
              physical_environment: record.physical_environment,
              cluster: record.cluster,
              deployment_name: record.deployment_name,
              created_at: record.created_at,
              updated_at: record.updated_at,
              deleted_at: record.deleted_at,
              org_id: metadata&.owner_id,
              repo_id: metadata&.repository_id,
              attestation_id: metadata&.attestation_id,
              artifact_metadata_id: record.artifact_metadata_id,
            })
          end
        end

        storage_record_ids.each_slice(500) do |batch_ids|
          storage_records = ArtifactStorageRecordModel.where(id: batch_ids).to_a

          storage_records.each do |record|
            metadata = metadata_details_by_id[record.artifact_metadata_id]

            ArtifactRegistryHydroMessageManager.send_delete_hydro_message_for_storage_record({
              id: record.id,
              attestation_id: metadata&.attestation_id,
              digest: metadata&.digest,
              registry_url: record.registry_url,
              registry_repository_name: record.registry_repository_name,
              artifact_url: record.artifact_url,
              artifact_path: record.artifact_path,
              source_registry: record.source_registry,
              created_at: record.created_at,
              updated_at: record.updated_at,
              deleted_at: record.deleted_at,
              repo_id: metadata&.repository_id,
              org_id: metadata&.owner_id,
              actor_id: record.actor_id,
              integration_id: record.integration_id,
            })
          end
        end
      end

      sig do
        params(items: Iterators::Items, metadata_ids: T::Array[Integer]).returns(T::Hash[Integer, ArtifactMetadataDetails])
      end
      def metadata_details_by_id_for(items, metadata_ids)
        metadata_id_set = metadata_ids.to_set

        items.each_with_object(T.let({}, T::Hash[Integer, ArtifactMetadataDetails])) do |(metadata_id, row), details_by_id|
          normalized_metadata_id = Integer(metadata_id)
          next unless metadata_id_set.include?(normalized_metadata_id)

          details_by_id[normalized_metadata_id] = ArtifactMetadataDetails.new(
            digest: T.cast(row[:digest], T.nilable(String)),
            owner_id: T.cast(row[:owner_id], T.nilable(Integer)),
            repository_id: T.cast(row[:repository_id], T.nilable(Integer)),
            attestation_id: T.cast(row[:attestation_id], T.nilable(Integer)),
          )
        end
      end
    end
  end
end

if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::MarkArtifactMetadataRecordsDeletedForPurgedRepositories.new(args).run
end
