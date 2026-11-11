# typed: false
# frozen_string_literal: true

class RepositoryActionsOIDCConfig < ApplicationRecord::Domain::Oidc
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  destroy_in_background_with :repository

  KEY_CUSTOM_SUB_CLAIM_DISABLED = "custom_sub_claim_disabled"
  KEY_CUSTOM_SUB_CLAIM_TEMPLATE = "include_claim_keys"
  KEY_USE_IMMUTABLE_SUBJECT = "use_immutable_subject"

  # Repositories created or renamed after this date automatically use immutable subject claims.
  # Must stay in sync with ImmutableSubjectCutoffDate in run-service/sdk/oidc/oidc.go
  IMMUTABLE_SUBJECT_CUTOFF_DATE = Time.utc(2026, 7, 15).freeze

  # Format the classic sub claim prefix: "repo:owner/repo"
  def self.sub_claim_prefix(repo)
    "repo:#{repo.name_with_display_owner}"
  end

  # Format the immutable sub claim prefix with names and database IDs:
  # "repo:owner_login@owner_id/repo_name@repo_id"
  def self.immutable_sub_claim_prefix(repo)
    "repo:#{repo.owner_display_login}@#{repo.owner_id}/#{repo.name}@#{repo.id}"
  end

  # Whether immutable subject is automatically enabled based on creation/rename date
  def self.auto_enabled?(repo)
    return true if repo.created_at > IMMUTABLE_SUBJECT_CUTOFF_DATE

    namespace_changed_at = ActiveRecord::Base.connected_to(role: :reading) do
      RepositoryRedirect.where(repository_id: repo.id).maximum(:created_at)
    end

    namespace_changed_at.present? && namespace_changed_at > IMMUTABLE_SUBJECT_CUTOFF_DATE
  end

  # get the configuration map of Actions OIDC configuration, for the repository
  def self.get_configurations(repo_id)
    entity = RepositoryActionsOIDCConfig.where(repository_id: repo_id)&.first
    entity.present? ? entity.configuration : {}
  end

  # get the value of Actions OIDC configuration given the key, for the repository
  def self.get_configuration(repo_id, key, default_value = nil)
    map = get_configurations(repo_id)
    if map.present? && map.has_key?(key)
      map[key]
    else
      default_value
    end
  end

  # get the map of Actions OIDC configuration for the repository
  def self.update_configurations(repo_id, configuration)
    entity = RepositoryActionsOIDCConfig.where(repository_id: repo_id)&.first
    if entity.present?
      entity.update!(configuration: entity.configuration.merge(configuration))
      :updated
    else
      entity = RepositoryActionsOIDCConfig.create!(repository_id: repo_id, configuration: configuration)
      :created
    end
  end
end
