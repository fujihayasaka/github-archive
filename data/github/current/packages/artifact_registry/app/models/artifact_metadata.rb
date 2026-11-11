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
  scope :not_active, -> { where.not(status: :active) }
  scope :not_deleted, -> { where.not(status: :deleted) }

  SORT_OPTIONS = {
    "created-desc" => { created_at: :desc, id: :desc },
    "created-asc" => { created_at: :asc, id: :asc },
    "updated-desc" => { updated_at: :desc, id: :desc },
    "updated-asc" => { updated_at: :asc, id: :asc },
  }.freeze

  DEFAULT_SORT = "created-desc"

  sig { params(sort: T.nilable(String)).returns(T::Boolean) }
  def self.valid_sort?(sort)
    SORT_OPTIONS.key?(sort)
  end

  validates :name, length: { maximum: 256 }
  validates :version, length: { maximum: 128 }, allow_nil: true

  validates :digest, length: { maximum: 256 }, allow_nil: true
  validates :digest, uniqueness: { scope: :repository_id, message: "must be unique within the repository" }, allow_nil: true
  validates :digest, format: { with: /\Asha256:[a-fA-F0-9]{64}\z/, message: "must be a valid SHA256 digest" }

  def soft_delete_if_standalone
    return if deleted_at.present?
    soft_delete if standalone?
  end

  def standalone?
    deployment_records.active.empty? && storage_records.active.empty?
  end

  def soft_delete
    self.update!(deleted_at: Time.now, status: "Deleted")
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String], repository_id: Integer, attestation_id: T.nilable(Integer)).returns(T.untyped) }
  def self.create(org, data, repository_id, attestation_id)
    ArtifactMetadata.create!(
      owner_id: org.id,
      digest: data[:digest],
      repository_id: repository_id,
      attestation_id: attestation_id,
      name: data[:name],
      version: data[:version]
    )
  end

  sig { params(owner_id: Integer, digest: String, repository_ids: T::Array[Integer]).returns(T::Hash[Integer, ArtifactMetadata]) }
  def self.fetch_and_index_by_repo_id(owner_id, digest, repository_ids)
    ArtifactMetadata.where(
      owner_id: owner_id,
      digest: digest,
      repository_id: repository_ids
    ).index_by(&:repository_id)
  end

  sig { params(owner_id: Integer, digests: T::Array[String], repository_ids: T::Array[Integer]).returns(T::Hash[[Integer, String], Integer]) }
  def self.bulk_fetch_ids_by_digest_and_repo_id(owner_id, digests, repository_ids)
    ArtifactMetadata.where(
      owner_id: owner_id,
      digest: digests,
      repository_id: repository_ids
    ).pluck(:repository_id, :digest, :id)
     .each_with_object({}) { |(repo_id, digest, id), hash| hash[[repo_id, digest]] = id }
  end

  # Soft delete records in bulk using a subquery to select records that do not
  # have any active deployment or storage records associated with them.
  sig { params(ids: T::Array[Integer]).returns(T.untyped) }
  def self.soft_delete_by_ids(ids)
    return 0 if ids.empty?

    now = connection.quote(Time.now)
    ids_list = ids.map { |id| connection.quote(id) }.join(",")

    # perform the update using a single SQL statement with LEFT JOINs
    # to identify records without associated active deployment or storage records
    # the query uses the artifact_metadata_id indexes in the artifact_deployment_records
    # and artifact_storage_records tables for efficiency
    connection.execute(<<~SQL)
      UPDATE artifact_metadata
      LEFT JOIN artifact_deployment_records
        ON artifact_deployment_records.artifact_metadata_id = artifact_metadata.id
        AND artifact_deployment_records.deleted_at IS NULL
      LEFT JOIN artifact_storage_records
        ON artifact_storage_records.artifact_metadata_id = artifact_metadata.id
        AND artifact_storage_records.deleted_at IS NULL
      SET artifact_metadata.deleted_at = #{now},
          artifact_metadata.status = 'Deleted'
      WHERE artifact_metadata.id IN (#{ids_list})
        AND artifact_deployment_records.id IS NULL
        AND artifact_storage_records.id IS NULL
    SQL
  end

  sig { params(org_id: Integer, page: Integer, per_page: Integer, sort: T.nilable(String)).returns(T::Array[{ artifact_metadata_id: Integer, owner_id: Integer, artifact_name: String, version: String, created_at: Time, updated_at: Time, attestation_id: T.nilable(Integer), repository_id: Integer, repository_name: String, integration_id: T.nilable(Integer), source_registry: T.nilable(String), tags: T::Array[String], deployment_count: Integer }]) }
  def self.artifacts_by_org_id(org_id:, page: 1, per_page: 25, sort: DEFAULT_SORT)
    offset = (page - 1) * per_page

    # Fetch artifact metadata records with repository to get repo name
    metadatas = includes(:deployment_records, :repository, :storage_records)
      .where(owner_id: org_id)
      .order(SORT_OPTIONS[valid_sort?(sort) ? sort : DEFAULT_SORT])
      .limit(per_page)
      .offset(offset)

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
      # Get the first source_registry and integration_id from storage_records, or nil if none exist
      source_registry = metadata.storage_records.first&.source_registry
      integration_id = metadata.storage_records.first&.integration_id

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
        integration_id: integration_id,
        tags: tags,
        deployment_count: deployment_count,
      }
    end
  end

  sig { params(repository_id: Integer).returns(T::Array[String]) }
  def self.deployed_runtime_risks_for_repository(repository_id)
    joins(deployment_records: :deployment_record_tags)
      .where(repository_id: repository_id)
      .where(artifact_deployment_records: { deleted_at: nil })
      .where(artifact_deployment_record_tags: { tag_name: "runtime-risk" })
      .distinct
      .pluck("artifact_deployment_record_tags.tag_value")
  end

  sig { params(org_id: Integer).returns(Integer) }
  def self.artifact_count_by_org_id(org_id:)
    where(owner_id: org_id).count
  end
end
