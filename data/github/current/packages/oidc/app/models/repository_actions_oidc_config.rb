# typed: false
# frozen_string_literal: true

class RepositoryActionsOIDCConfig < ApplicationRecord::Domain::Oidc
  KEY_CUSTOM_SUB_CLAIM_DISABLED = "custom_sub_claim_disabled"
  KEY_CUSTOM_SUB_CLAIM_TEMPLATE = "include_claim_keys"

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
