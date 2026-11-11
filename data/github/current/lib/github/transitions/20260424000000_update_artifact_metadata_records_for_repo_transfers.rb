# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdateArtifactMetadataRecordsForRepoTransfers < Base
      # This transition updates artifact metadata, deployment records, and storage records
      # whose repositories have been transferred to a new owner.
      # If the repository has been transferred to a user, the associated records
      # will be marked as deleted, since user-owned artifacts are not supported.

      class ArtifactMetadataModel < ApplicationRecord::ArtifactRegistry
        self.table_name = :artifact_metadata
        self.inheritance_column = :_type_disabled
      end

      class RepositoryModel < ApplicationRecord::Repositories
        self.table_name = :repositories
      end

      class ArtifactDeploymentRecordModel < ApplicationRecord::ArtifactRegistry
        self.table_name = :artifact_deployment_records
      end

      class ArtifactStorageRecordModel < ApplicationRecord::ArtifactRegistry
        self.table_name = :artifact_storage_records
      end

      iterate_over :database_table, params: {
        model_class: ArtifactMetadataModel,
        conditions: "deleted_at IS NULL",
        columns: %i[id owner_id repository_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        return if GitHub.enterprise?

        now = Time.current

        # Extract repository IDs and owner IDs for batch fetch
        repository_ids = items.values.map { |row| row[:repository_id] }.compact.uniq
        old_owner_ids = items.values.map { |row| row[:owner_id] }.compact.uniq

        repositories = RepositoryModel.where(id: repository_ids).index_by(&:id)
        # { repository_id => new_owner_id }
        potential_new_owner_ids = repositories.transform_values { |repo| repo.owner_id }
        old_users = User.where(id: old_owner_ids).index_by(&:id)
        new_users = User.where(id: potential_new_owner_ids.values).index_by(&:id)

        # For each metadata record, check if the repository has been transferred
        records_to_update = []

        items.each do |metadata_id, metadata_row|
          repository_id = metadata_row[:repository_id]
          old_owner_id = metadata_row[:owner_id]

          repository = repositories[repository_id]
          next unless repository

          old_owner = old_users[old_owner_id]
          # Only proceed if the old owner is an organization
          next unless old_owner&.organization?

          new_owner_id = potential_new_owner_ids[repository.id]

          # Check if repository owner differs from metadata owner (transfer detected)
          next if old_owner_id == new_owner_id

          new_owner = new_users[new_owner_id]
          # Check if transferred to a user or organization
          transferred_to_user = new_owner&.user?

          records_to_update << {
            metadata_id: metadata_id,
            new_owner_id: new_owner_id,
            transferred_to_user: transferred_to_user,
          }
        end

        return if records_to_update.empty?

        if dry_run?
          log "Dry run: would update #{records_to_update.size} artifact records"
          return
        end

        # Separate records by transfer type for efficient batch updates
        transferred_to_org = records_to_update.reject { |r| r[:transferred_to_user] }
        transferred_to_user = records_to_update.select { |r| r[:transferred_to_user] }

        # Update records transferred to organization (only owner change)
        update_metadata_for_org_transfer(transferred_to_org, now) if transferred_to_org.any?

        # Update records transferred to user (mark as deleted)
        update_metadata_for_user_transfer(transferred_to_user, now) if transferred_to_user.any?

        log "Updated #{records_to_update.size} artifact records for repository transfers"
      end

      private

      sig { params(records: T::Array[T::Hash[Symbol, T.any(Integer, T::Boolean)]], current_time: Time).void }
      def update_metadata_for_org_transfer(records, current_time)
        metadata_ids = records.map { |r| r[:metadata_id] }
        owner_id_map = records.index_by { |r| r[:metadata_id] }

        # Update associated deployment records
        metadata_ids.each do |metadata_id|
          write_to(model_class: ArtifactDeploymentRecordModel) do
            new_owner_id = owner_id_map[metadata_id][:new_owner_id]
            ArtifactDeploymentRecordModel
              .where(artifact_metadata_id: metadata_id, deleted_at: nil)
              .update_all(owner_id: new_owner_id, updated_at: current_time)
          end
        end

        # Update artifact metadata - just change owner
        metadata_ids.each do |metadata_id|
          write_to(model_class: ArtifactMetadataModel) do
            new_owner_id = owner_id_map[metadata_id][:new_owner_id]
            ArtifactMetadataModel.where(id: metadata_id).update_all(
              owner_id: new_owner_id,
              attestation_id: nil,
              updated_at: current_time
            )
          end
        end
      end

      sig { params(records: T::Array[T::Hash[Symbol, T.any(Integer, T::Boolean)]], current_time: Time).void }
      def update_metadata_for_user_transfer(records, current_time)
        metadata_ids = records.map { |r| r[:metadata_id] }
        owner_id_map = records.index_by { |r| r[:metadata_id] }

        # Update associated deployment records - mark as deleted
        metadata_ids.each do |metadata_id|
          write_to(model_class: ArtifactDeploymentRecordModel) do
            new_owner_id = owner_id_map[metadata_id][:new_owner_id]
            ArtifactDeploymentRecordModel
              .where(artifact_metadata_id: metadata_id, deleted_at: nil)
              .update_all(owner_id: new_owner_id, deleted_at: current_time, updated_at: current_time)
          end
        end

        # Update associated storage records - mark as deleted
        write_to(model_class: ArtifactStorageRecordModel) do
          ArtifactStorageRecordModel
            .where(artifact_metadata_id: metadata_ids, deleted_at: nil)
            .update_all(deleted_at: current_time, updated_at: current_time)
        end

        # Update artifact metadata - change owner and mark as deleted
        metadata_ids.each do |metadata_id|
          write_to(model_class: ArtifactMetadataModel) do
            new_owner_id = owner_id_map[metadata_id][:new_owner_id]
            ArtifactMetadataModel.where(id: metadata_id).update_all(
              owner_id: new_owner_id,
              attestation_id: nil,
              deleted_at: current_time,
              status: "Deleted",
              updated_at: current_time
            )
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::UpdateArtifactMetadataRecordsForRepoTransfers.new(args).run
end
