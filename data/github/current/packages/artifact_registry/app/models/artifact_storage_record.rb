# typed: true
# frozen_string_literal: true

class ArtifactStorageRecord < ApplicationRecord::Domain::ArtifactRegistry
  SOURCE_REGISTRIES = [
    SOURCE_REGISTRY_ARTIFACTORY = "jfrog-artifactory"
  ].freeze

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

  sig { params(registry_urls: T::Array[String], owner_id: Integer).returns(T::Array[Integer]) }
  def self.repository_ids_for_owner_and_registries(registry_urls:, owner_id:)
    joins(:artifact_metadata)
      .where(registry_url: registry_urls)
      .where(artifact_metadata: { owner_id: owner_id })
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(artifact_registries: T::Array[String], owner_id: Integer).returns(T::Array[Integer]) }
  def self.repository_ids_for_owner_and_artifact_registries(artifact_registries:, owner_id:)
    joins(:artifact_metadata)
      .where(source_registry: artifact_registries)
      .where(artifact_metadata: { owner_id: owner_id })
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(owner_id: Integer, repository_ids: T::Array[Integer], limit: Integer).returns(T::Array[{ registry_url: String, count: Integer }]) }
  def self.registry_urls_for_owner_and_repositories(owner_id:, repository_ids:, limit: 25)
    scope = joins(:artifact_metadata)
      .where(artifact_metadata: { owner_id: owner_id })
    unless repository_ids.empty?
      scope = scope.where(artifact_metadata: { repository_id: repository_ids })
    end
    # Tell Sorbet this is a Hash, not an Integer
    grouped_counts = T.cast(scope.group(:registry_url).order(:registry_url).limit(limit).count, T::Hash[String, Integer])
    grouped_counts.map do |registry_url, count|
      { registry_url: registry_url, count: count }
    end
  end
end
