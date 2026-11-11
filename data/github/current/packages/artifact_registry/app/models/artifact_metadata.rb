# typed: true
# frozen_string_literal: true

class ArtifactMetadata < ApplicationRecord::Domain::ArtifactRegistry
  include ::Repositories::BelongsToRepository

  has_many :storage_records,
    class_name: "ArtifactStorageRecord",
    foreign_key: :artifact_metadata_id,
    inverse_of: :artifact_metadata,
    dependent: :destroy

  has_many :deployment_records,
    class_name: "ArtifactDeploymentRecord",
    foreign_key: :artifact_metadata_id,
    inverse_of: :artifact_metadata,
    dependent: :destroy

  belongs_to :owner, class_name: "User"
  belongs_to_repository_via_domain

  validates :tenant_id, presence: true
  validates :owner_id, presence: true
  validates :repository_id, presence: true
  validates :name, presence: true

  enum :status, { active: "Active", eol: "EOL", deleted: "Deleted" }, validate: true

  validates :name, length: { maximum: 256 }
  validates :version, length: { maximum: 128 }, allow_nil: true

  validates :digest, length: { maximum: 256 }, allow_nil: true
  validates :digest, uniqueness: { scope: :repository_id, message: "must be unique within the repository" }, allow_nil: true
  validates :digest, format: { with: /\Asha256:[a-fA-F0-9]{64}\z/, message: "must be a valid SHA256 digest" }

  def standalone?
    deployment_records.active.empty? && storage_records.empty?
  end

  def soft_delete
    self.update!(deleted_at: Time.now)
    self.update!(status: "Deleted")
  end

  sig { params(org_id: Integer, limit: Integer).returns(T::Array[{ artifact_metadata_id: Integer, owner_id: Integer, artifact_name: String, version: String, created_at: Time, updated_at: Time, attestation_id: T.nilable(Integer), repository_id: Integer, repository_name: String, source_registry: T.nilable(String), tags: T::Array[String], deployment_count: Integer }]) }
  def self.artifacts_by_org_id(org_id:, limit: 25)
    # Fetch artifact metadata records with repository to get repo name
    metadatas = includes(:deployment_records, :repository, :storage_records)
      .where(owner_id: org_id)
      .order(created_at: :desc)
      .limit(limit)

    # Collect all artifact_metadata_ids
    artifact_metadata_ids = metadatas.map(&:id)

    # Fetch all deployment records for these artifact_metadata_ids
    deployment_records = ArtifactDeploymentRecord.where(artifact_metadata_id: artifact_metadata_ids)

    # Map deployment_record_id to artifact_metadata_id
    deployment_record_id_to_metadata_id = deployment_records.each_with_object({}) do |dr, h|
      h[dr.id] = dr.artifact_metadata_id
    end

    # Fetch only runtime risk tags for these deployment records in a single query
    tags_by_metadata_id = Hash.new { |h, k| h[k] = [] }
    ArtifactDeploymentRecordTag
      .where(deployment_record_id: deployment_record_id_to_metadata_id.keys)
      .where(tag_name: "runtime-risk")
      .pluck(:deployment_record_id, :tag_value)
      .each do |deployment_record_id, tag_value|
        metadata_id = deployment_record_id_to_metadata_id[deployment_record_id]
        tags_by_metadata_id[metadata_id] << tag_value if metadata_id
      end

    # Remove duplicates and sort tags for each metadata_id
    tags_by_metadata_id.each do |metadata_id, tags|
      tags_by_metadata_id[metadata_id] = tags.uniq.sort
    end

    # Build the result array
    metadatas.map do |metadata|
      deployment_count = metadata.deployment_records.count
      tags = tags_by_metadata_id[metadata.id] || []
      # Get the first source_registry from storage_records, or nil if none exist
      source_registry = metadata.storage_records.first&.source_registry

      {
        artifact_metadata_id: metadata.id,
        owner_id: metadata.owner_id,
        artifact_name: metadata.name,
        version: metadata.version,
        created_at: metadata.created_at,
        updated_at: metadata.updated_at,
        attestation_id: metadata.attestation_id,
        repository_id: metadata.repository_id,
        repository_name: metadata.repository&.name || "",
        source_registry: source_registry,
        tags: tags,
        deployment_count: deployment_count,
      }
    end
  end

  sig { params(org_id: Integer).returns(Integer) }
  def self.artifact_count_by_org_id(org_id:)
    where(owner_id: org_id).count
  end
end
