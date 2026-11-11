# typed: false
# frozen_string_literal: true

module Organization::ConfigRepoDependency
  extend ActiveSupport::Concern

  CONFIG_REPO_NAME = ".github"
  CONFIG_PRIVATE_REPO_NAME = ".github-private"

  included do
    # An org's configuration_repository is located at a public repo named '.github'
    has_one :configuration_repository, ->(org) do
      if org.organization?
        public_scope.active.where(name: CONFIG_REPO_NAME)
      else
        none
      end
    end, foreign_key: :owner_id, inverse_of: :owner, class_name: :Repository

    # An org's private_configuration_repository is located at a private repo named '.github-private'
    has_one :private_configuration_repository, ->(org) do
      if org.organization?
        private_not_internal_scope.active.where(name: CONFIG_PRIVATE_REPO_NAME)
      else
        none
      end
    end, foreign_key: :owner_id, inverse_of: :owner, class_name: :Repository
  end

  def config_repo_name
    CONFIG_REPO_NAME
  end

  def has_configuration_repository?
    configuration_repository.present?
  end
end
