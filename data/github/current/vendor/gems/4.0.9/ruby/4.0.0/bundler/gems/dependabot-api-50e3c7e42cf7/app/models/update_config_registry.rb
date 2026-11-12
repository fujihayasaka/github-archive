# frozen_string_literal: true

# Reference to a `Registry` by name
# Might resolve to a `Registry` owned by the config's repo, or the config's repo's owner
class UpdateConfigRegistry < ApplicationRecord
  class RegistryNotFound < StandardError; end

  belongs_to :update_config

  validates :registry_name, presence: true

  def registry
    repo_registry = update_config.repo.registries.find_by(name: registry_name)
    return repo_registry if repo_registry

    owner_registry = update_config.repo.account.registries.find_by(name: registry_name)
    return owner_registry if owner_registry

    raise RegistryNotFound, registry_name
  end
end
