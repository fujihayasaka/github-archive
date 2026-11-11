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

  ArtifactIdsByRepositoryDigest = T.type_alias { T::Hash[[Integer, String], Integer] }

  sig { params(sort: T.nilable(String)).returns(T::Boolean) }
  def self.valid_sort?(sort)
    SORT_OPTIONS.key?(sort)
  end

  validates :name, length: { maximum: 256 }
  validates :version, length: { maximum: 128 }, allow_nil: true

  validates :digest, length: { maximum: 256 }, allow_nil: true
  validates :digest, uniqueness: { scope: :repository_id, message: "must be unique within the repository" }, allow_nil: true
  validates :digest, format: { with: /\Asha256:[a-fA-F0-9]{64}\z/, message: "must be a valid SHA256 digest" }

  sig { params(query: T.nilable(String)).returns(T.untyped) }
  def self.search_by_name(query)
    return all if query.blank?
    where("name LIKE ?", "%#{sanitize_sql_like(query.to_s)}%")
  end

  def soft_delete_if_standalone
    return if deleted_at.present?
    soft_delete if standalone?
  end

  def standalone?
    # Check if there are no active deployment or storage associations
    !deployment_records.active.exists? && !storage_records.active.exists?
  end

  def soft_delete
    self.update!(deleted_at: Time.now, status: "Deleted")
  end

  sig { params(org: Organization, data: T::Hash[Symbol, String], repository_id: Integer, attestation_id: T.nilable(Integer)).returns(T.untyped) }
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

  sig { params(org: Organization, data: T::Hash[Symbol, String], repository_id: Integer, attestation_id: T.nilable(Integer)).returns(ArtifactMetadata) }
  def self.find_or_create_by_digest!(org, data, repository_id, attestation_id)
    digest = T.let(data.fetch(:digest, ""), String)

    existing_artifact = find_revivable_by_digest(org.id, digest, repository_id)
    return revive!(existing_artifact, data, attestation_id) if existing_artifact

    create(org, data, repository_id, attestation_id)
  rescue ActiveRecord::RecordNotUnique
    existing_artifact = find_revivable_by_digest(org.id, digest, repository_id)
    return revive!(existing_artifact, data, attestation_id) if existing_artifact

    find_by!(owner_id: org.id, repository_id: repository_id, digest: digest)
  end

  sig { params(owner_id: Integer, digest: String, repository_ids: T::Array[Integer]).returns(T::Hash[Integer, ArtifactMetadata]) }
  def self.fetch_and_index_by_repo_id(owner_id, digest, repository_ids)
    ArtifactMetadata.where(
      owner_id: owner_id,
      digest: digest,
      repository_id: repository_ids,
      deleted_at: nil
    ).where.not(status: statuses[:deleted]).index_by(&:repository_id)
  end

  sig { params(owner_id: Integer, digests: T::Array[String], repository_ids: T::Array[Integer]).returns(ArtifactIdsByRepositoryDigest) }
  def self.fetch_active_ids_by_digest_and_repo_id(owner_id, digests, repository_ids)
    where(
      owner_id: owner_id,
      digest: digests,
      repository_id: repository_ids,
    ).where.not(status: statuses[:deleted]).pluck(:repository_id, :digest, :id)
     .each_with_object({}) { |(repo_id, digest, id), hash| hash[[repo_id, digest]] = id }
  end

  sig { params(owner_id: Integer, digests: T::Array[String], repository_ids: T::Array[Integer]).returns(ArtifactIdsByRepositoryDigest) }
  def self.revive_and_fetch_deleted_ids_by_digest_and_repo_id(owner_id, digests, repository_ids)
    revivable_records = where(
      owner_id: owner_id,
      digest: digests,
      repository_id: repository_ids,
    ).where("artifact_metadata.deleted_at IS NOT NULL OR artifact_metadata.status = ?", statuses[:deleted])

    return {} unless revivable_records.exists?

    # Create a map of [repository_id, digest] to artifact_metadata_id for the revivable records to efficiently check ownership and update them
    # This map is returned after the records have been updated
    revivable_record_map = revivable_records.pluck(:repository_id, :digest, :id)
      .each_with_object({}) { |(repo_id, digest, id), hash| hash[[repo_id, digest]] = id }

    # Create an array of the first element of the keys (repository_id) from the revivable_record_map
    # and used to check that all repositories are owned by the organization associated with the request
    repository_ids_to_revive = revivable_record_map.keys.map { |key| Integer(key.first) }.uniq
    owned_repository_ids = Repository.where(id: repository_ids_to_revive, owner_id: owner_id).pluck(:id)
    missing_repository_ids = repository_ids_to_revive - owned_repository_ids

    if missing_repository_ids.any?
      raise ActiveRecord::RecordNotFound, "Repository ids #{missing_repository_ids.join(', ')} are not owned by #{owner_id}"
    end

    revivable_records.update_all(deleted_at: nil, status: statuses[:active], updated_at: Time.current)

    revivable_record_map
  end

  sig { params(owner_id: Integer, digests: T::Array[String], repository_ids: T::Array[Integer]).returns(ArtifactIdsByRepositoryDigest) }
  def self.fetch_all_artifact_ids_by_digest_and_repo_id(owner_id, digests, repository_ids)
    active_ids = fetch_active_ids_by_digest_and_repo_id(owner_id, digests, repository_ids)
    revived_ids = revive_and_fetch_deleted_ids_by_digest_and_repo_id(owner_id, digests, repository_ids)
    active_ids.merge(revived_ids)
  end

  sig { params(owner_id: Integer, digest: T.nilable(String), repository_id: Integer).returns(T.nilable(ArtifactMetadata)) }
  def self.find_revivable_by_digest(owner_id, digest, repository_id)
    return if digest.nil?

    ArtifactMetadata.where(owner_id: owner_id, digest: digest, repository_id: repository_id).first
  end

  sig { params(artifact: ArtifactMetadata, data: T::Hash[Symbol, String], attestation_id: T.nilable(Integer)).returns(ArtifactMetadata) }
  def self.revive!(artifact, data, attestation_id)
    return artifact if artifact.deleted_at.nil? && !artifact.deleted?

    if Repository.exists?(id: artifact.repository_id, owner_id: artifact.owner_id)
      artifact.update!(
        attestation_id: attestation_id,
        deleted_at: nil,
        name: data[:name],
        status: "Active",
        version: data[:version],
      )
      artifact
    else
      raise ActiveRecord::RecordNotFound, "Repository #{artifact.repository_id} is not owned by #{artifact.owner_id}"
    end
  end

  # Soft delete records in bulk using a batched approach to reduce lock duration.
  # Batching keeps individual lock durations minimal while re-checking protects against race conditions.
  sig { params(ids: T::Array[Integer]).returns(T.untyped) }
  def self.soft_delete_by_ids(ids)
    return 0 if ids.empty?

    ActiveRecord::Base.connected_to_many(
      [ApplicationRecord::ArtifactRegistry], role: :writing
    ) do
      # Query 2: Update only the identified standalone artifacts in batches of 100
      # Re-checks conditions on each batch to protect against race conditions between queries
      now = connection.quote(Time.now)

      ids.each_slice(100) do |batch_ids|
        batch_ids_list = batch_ids.map { |id| connection.quote(id) }.join(",")

        connection.execute(<<~SQL)
          UPDATE artifact_metadata
          SET artifact_metadata.deleted_at = #{now},
              artifact_metadata.status = 'Deleted'
          WHERE artifact_metadata.id IN (#{batch_ids_list})
            AND NOT EXISTS (
              SELECT 1 FROM artifact_deployment_records
              WHERE artifact_deployment_records.artifact_metadata_id = artifact_metadata.id
              AND artifact_deployment_records.deleted_at IS NULL
            )
            AND NOT EXISTS (
              SELECT 1 FROM artifact_storage_records
              WHERE artifact_storage_records.artifact_metadata_id = artifact_metadata.id
              AND artifact_storage_records.deleted_at IS NULL
            )
        SQL
      end

      ids.length
    end
  end

  sig { params(org_id: Integer, page: Integer, per_page: Integer, query: T::Hash[Symbol, T.untyped], repository_ids: T.nilable(T::Array[Integer])).returns(T::Array[{ artifact_metadata_id: Integer, owner_id: Integer, artifact_name: String, version: String, created_at: Time, updated_at: Time, attestation_id: T.nilable(Integer), repository_id: Integer, repository_name: String, integration_id: T.nilable(Integer), source_registry: T.nilable(String), tags: T::Array[String], deployment_count: Integer }]) }
  def self.artifacts_by_org_id(org_id:, page: 1, per_page: 25, query: {}, repository_ids: nil)
    search_text = query[:search_text]
    sort = query[:sort]
    filters = query[:filters] || {}
    offset = (page - 1) * per_page

    # Fetch artifact metadata records with repository to get repo name
    scope = includes(:deployment_records, :repository, :storage_records)
      .where(owner_id: org_id)
      .merge(search_by_name(search_text))
    scope = scope.where(repository_id: repository_ids) if repository_ids
    scope = apply_filters(scope, filters)
    metadatas = scope
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
    ArtifactDeploymentRecordTag
      .where(tag_name: "runtime-risk")
      .joins(deployment_record: :artifact_metadata)
      .where(artifact_metadata: { repository_id: repository_id })
      .where(artifact_deployment_records: { deleted_at: nil })
      .pluck(:tag_value)
      .uniq
  end

  sig { params(org_id: Integer, query: T::Hash[Symbol, T.untyped], repository_ids: T.nilable(T::Array[Integer])).returns(Integer) }
  def self.artifact_count_by_org_id(org_id:, query: {}, repository_ids: nil)
    search_text = query[:search_text]
    filters = query[:filters] || {}
    scope = where(owner_id: org_id).merge(search_by_name(search_text))
    scope = scope.where(repository_id: repository_ids) if repository_ids
    scope = apply_filters(scope, filters)
    scope.count
  end

  # Apply structured filter parameters to a scope using EXISTS subqueries
  # to avoid duplicate rows from JOINs.
  sig { params(scope: T.untyped, filters: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def self.apply_filters(scope, filters)
    return scope if filters.empty?

    scope = apply_source_registry_filter(scope, filters)
    scope = apply_runtime_risk_filter(scope, filters)
    scope = apply_registry_url_filter(scope, filters)
    scope = apply_has_deployments_filter(scope, filters)
    scope = apply_date_filter(scope, filters, :created)
    scope = apply_date_filter(scope, filters, :updated)
    scope
  end

  sig { params(scope: T.untyped, filters: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def self.apply_source_registry_filter(scope, filters)
    if filters[:source_registry].present?
      scope = scope.where(
        "EXISTS (SELECT 1 FROM artifact_storage_records WHERE artifact_storage_records.artifact_metadata_id = artifact_metadata.id AND artifact_storage_records.deleted_at IS NULL AND artifact_storage_records.source_registry = ?)",
        filters[:source_registry]
      )
    end

    if filters[:exclude_source_registry].present?
      scope = scope.where(
        "NOT EXISTS (SELECT 1 FROM artifact_storage_records WHERE artifact_storage_records.artifact_metadata_id = artifact_metadata.id AND artifact_storage_records.deleted_at IS NULL AND artifact_storage_records.source_registry = ?)",
        filters[:exclude_source_registry]
      )
    end

    scope
  end

  sig { params(scope: T.untyped, filters: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def self.apply_runtime_risk_filter(scope, filters)
    if filters[:runtime_risks].present?
      scope = scope.where(
        "EXISTS (SELECT 1 FROM artifact_deployment_records INNER JOIN artifact_deployment_record_tags ON artifact_deployment_record_tags.deployment_record_id = artifact_deployment_records.id WHERE artifact_deployment_records.artifact_metadata_id = artifact_metadata.id AND artifact_deployment_records.deleted_at IS NULL AND artifact_deployment_record_tags.tag_name = 'runtime-risk' AND artifact_deployment_record_tags.tag_value IN (?))",
        filters[:runtime_risks]
      )
    end

    if filters[:exclude_runtime_risks].present?
      scope = scope.where(
        "NOT EXISTS (SELECT 1 FROM artifact_deployment_records INNER JOIN artifact_deployment_record_tags ON artifact_deployment_record_tags.deployment_record_id = artifact_deployment_records.id WHERE artifact_deployment_records.artifact_metadata_id = artifact_metadata.id AND artifact_deployment_records.deleted_at IS NULL AND artifact_deployment_record_tags.tag_name = 'runtime-risk' AND artifact_deployment_record_tags.tag_value IN (?))",
        filters[:exclude_runtime_risks]
      )
    end

    scope
  end

  sig { params(scope: T.untyped, filters: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def self.apply_registry_url_filter(scope, filters)
    if filters[:registry_urls].present?
      scope = scope.where(
        "EXISTS (SELECT 1 FROM artifact_storage_records WHERE artifact_storage_records.artifact_metadata_id = artifact_metadata.id AND artifact_storage_records.deleted_at IS NULL AND artifact_storage_records.registry_url IN (?))",
        filters[:registry_urls]
      )
    end

    if filters[:exclude_registry_urls].present?
      scope = scope.where(
        "NOT EXISTS (SELECT 1 FROM artifact_storage_records WHERE artifact_storage_records.artifact_metadata_id = artifact_metadata.id AND artifact_storage_records.deleted_at IS NULL AND artifact_storage_records.registry_url IN (?))",
        filters[:exclude_registry_urls]
      )
    end

    scope
  end

  sig { params(scope: T.untyped, filters: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def self.apply_has_deployments_filter(scope, filters)
    if filters[:has_deployments] == true
      scope = scope.where(
        "EXISTS (SELECT 1 FROM artifact_deployment_records WHERE artifact_deployment_records.artifact_metadata_id = artifact_metadata.id AND artifact_deployment_records.deleted_at IS NULL)"
      )
    end

    if filters[:exclude_has_deployments] == true
      scope = scope.where(
        "NOT EXISTS (SELECT 1 FROM artifact_deployment_records WHERE artifact_deployment_records.artifact_metadata_id = artifact_metadata.id AND artifact_deployment_records.deleted_at IS NULL)"
      )
    end

    scope
  end

  sig { params(scope: T.untyped, filters: T::Hash[Symbol, T.untyped], field: Symbol).returns(T.untyped) }
  def self.apply_date_filter(scope, filters, field)
    filter = filters[field]
    return scope unless filter.is_a?(Hash)

    column = field == :created ? "artifact_metadata.created_at" : "artifact_metadata.updated_at"
    operator = filter[:operator]
    value = filter[:value]

    case operator
    when ">"
      if value.present?
        end_time = Time.zone.parse(value.to_s)&.end_of_day
        scope = scope.where("#{column} > ?", end_time) if end_time
      end
    when ">="
      if value.present?
        start_time = Time.zone.parse(value.to_s)&.beginning_of_day
        scope = scope.where("#{column} >= ?", start_time) if start_time
      end
    when "<"
      if value.present?
        start_time = Time.zone.parse(value.to_s)&.beginning_of_day
        scope = scope.where("#{column} < ?", start_time) if start_time
      end
    when "<="
      if value.present?
        end_time = Time.zone.parse(value.to_s)&.end_of_day
        scope = scope.where("#{column} <= ?", end_time) if end_time
      end
    when ".."
      start_date = filter[:start]
      end_date = filter[:end]
      if start_date.present? && end_date.present?
        start_time = Time.zone.parse(start_date.to_s)&.beginning_of_day
        end_time = Time.zone.parse(end_date.to_s)&.end_of_day
        if start_time && end_time
          scope = scope.where("#{column} BETWEEN ? AND ?", start_time, end_time)
        end
      end
    when "is"
      dates = Array(value)
      date_conditions = dates.filter_map do |d|
        next unless d.present?
        day_start = Time.zone.parse(d.to_s)&.beginning_of_day
        day_end = Time.zone.parse(d.to_s)&.end_of_day
        next unless day_start && day_end
        sanitize_sql_array(["#{column} BETWEEN ? AND ?", day_start, day_end])
      end
      scope = scope.where("(#{date_conditions.join(' OR ')})") if date_conditions.any?
    when "is_not"
      dates = Array(value)
      date_conditions = dates.filter_map do |d|
        next unless d.present?
        day_start = Time.zone.parse(d.to_s)&.beginning_of_day
        day_end = Time.zone.parse(d.to_s)&.end_of_day
        next unless day_start && day_end
        sanitize_sql_array(["#{column} NOT BETWEEN ? AND ?", day_start, day_end])
      end
      scope = scope.where(date_conditions.join(" AND ")) if date_conditions.any?
    end

    scope
  end
end
