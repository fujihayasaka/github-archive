# typed: true
# frozen_string_literal: true

class ArtifactStorageRecord < ApplicationRecord::Domain::ArtifactRegistry
  SOURCE_REGISTRIES = [
    SOURCE_REGISTRY_ARTIFACTORY = "jfrog-artifactory"
  ].freeze

  # Matches JFrog Artifactory-hosted registries on jfrog.io
  # All registry_url values are prefixed with 'https://'. This
  # is enforced by OpenAPI spec validation
  JFROG_IO_REGISTRY_URL_PATTERN = "https://%.jfrog.io%"
  JFROG_IO_REGISTRY_URL_REGEXP = "^https://[a-zA-Z0-9.-]+\\.jfrog\\.io(/|$)"

  belongs_to :artifact_metadata, inverse_of: :storage_records

  validates :artifact_metadata, presence: true
  validates :registry_url, presence: true

  validates :registry_url, length: { maximum: 256 }
  validates :registry_repository_name, length: { maximum: 128 }, allow_nil: true
  validates :artifact_url, length: { maximum: 152 }
  validates :artifact_path, length: { maximum: 512 }, allow_nil: true

  validates :source_registry, inclusion: {
    in: SOURCE_REGISTRIES,
    message: "%{value} is not a valid source registry"
  }, allow_nil: true

  scope :active, -> {
    where(deleted_at: nil)
  }

  after_commit :check_artifact_standalone, on: :update

  def check_artifact_standalone
    if T.unsafe(self).saved_change_to_artifact_metadata_id?
      check_previous_artifact_standalone
    elsif T.unsafe(self).saved_change_to_deleted_at?
      check_current_artifact_standalone
    end
  end

  # Called when a storage record's artifact association
  # has been updated. It checks whether the previously associated artifact
  # has any remaining active record associations and soft deletes it if not.
  def check_previous_artifact_standalone
    return unless self.saved_change_to_artifact_metadata_id?

    old_metadata_id = self.artifact_metadata_id_before_last_save
    return unless old_metadata_id

    GitHub.logger.debug("Enqueuing standalone check for artifact metadata #{old_metadata_id} after storage record artifact association was updated",
      "previous_artifact_metadata_id" => old_metadata_id,
      "storage_record_id" => self.id
    )
    ArtifactMetadataSoftDeleteIfStandaloneJob.perform_later(old_metadata_id)
  end

  # Called when the storage record's status has been updated to 'deleted'.
  # This indicates the record is marked as deleted. This method checks if the
  # currently associated artifact has any remaining active record associations
  # and soft deletes it if not.
  def check_current_artifact_standalone
    return unless self.saved_change_to_deleted_at?

    GitHub.logger.debug("Enqueuing standalone check for artifact metadata #{self.artifact_metadata_id} after storage record was marked as deleted",
      "artifact_metadata_id" => self.artifact_metadata_id,
      "storage_record_id" => self.id
    )
    ArtifactMetadataSoftDeleteIfStandaloneJob.perform_later(self.artifact_metadata_id)
  end

  # To avoid passing the applicaiton record around to different functions which can cause costly database lookups,
  # we can use the to_hash method to convert the record to a hash with all the necessary information for downstream
  # functions, including sending Hydro messages.
  def to_hash
    {
      id: id,
      attestation_id: artifact_metadata&.attestation_id,
      name: artifact_metadata&.name,
      digest: artifact_metadata&.digest,
      registry_url: registry_url,
      registry_repository_name: registry_repository_name,
      status: artifact_metadata&.status,
      artifact_url: artifact_url,
      artifact_path: artifact_path,
      source_registry: source_registry,
      created_at: created_at,
      updated_at: updated_at,
      deleted_at: deleted_at,
      repo_id: artifact_metadata&.repository_id,
      org_id: artifact_metadata&.owner_id,
      actor_id: actor_id,
      integration_id: integration_id,
    }
  end

  sig { params(owner_ids: T::Array[Integer], registry_urls: T::Array[String]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owners_and_registry_urls(owner_ids, registry_urls)
    joins(:artifact_metadata)
      .where(registry_url: registry_urls)
      .where(artifact_metadata: { owner_id: owner_ids })
      .where(deleted_at: nil)
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(owner_ids: T::Array[Integer], artifact_registries: T::Array[String]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owners_and_registries(owner_ids, artifact_registries)
    scope = joins(:artifact_metadata)
      .where(artifact_metadata: { owner_id: owner_ids })
      .where(deleted_at: nil)

    if artifact_registries.include?(SOURCE_REGISTRY_ARTIFACTORY)
      scope = scope.where(
        "source_registry IN (:filters) OR (registry_url LIKE :jfrog_host_pattern AND registry_url REGEXP :regex)",
        filters: artifact_registries,
        jfrog_host_pattern: JFROG_IO_REGISTRY_URL_PATTERN,
        regex: JFROG_IO_REGISTRY_URL_REGEXP,
      )
    else
      scope = scope.where(source_registry: artifact_registries)
    end

    scope
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(owner_id: Integer, repository_ids: T::Array[Integer], limit: Integer, search_term: T.nilable(String)).returns(T::Array[{ registry_url: String, count: Integer }]) }
  def self.registry_urls_for_owner_and_repositories(owner_id:, repository_ids:, limit: 25, search_term: nil)
    scope = joins(:artifact_metadata)
      .where(artifact_metadata: { owner_id: owner_id })
    unless repository_ids.empty?
      scope = scope.where(artifact_metadata: { repository_id: repository_ids })
    end
    if search_term.present?
      escaped = sanitize_sql_like(search_term)
      scope = scope.where("registry_url LIKE ?", "%#{escaped}%")
    end
    # Tell Sorbet this is a Hash, not an Integer
    grouped_counts = T.cast(scope.group(:registry_url).order(:registry_url).limit(limit).count, T::Hash[String, Integer])
    grouped_counts.map do |registry_url, count|
      { registry_url: registry_url, count: count }
    end
  end
end
