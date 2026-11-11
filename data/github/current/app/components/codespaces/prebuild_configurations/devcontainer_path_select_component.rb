# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::DevcontainerPathSelectComponent < ApplicationComponent
  def initialize(repository:, initial_branch_ref: nil, devcontainer_path: nil, pickable_devcontainers: nil)
    @repository = repository
    @initial_branch_ref = initial_branch_ref
    @devcontainer_path = devcontainer_path
    @pickable_devcontainers = pickable_devcontainers
  end

  DEFAULT_CODESPACES_CONFIGURATION = "Default Codespaces Configuration"

  def devcontainer_path
    @devcontainer_path.presence || (pickable_devcontainers.first&.path if Codespaces::DevContainer::PATHS.include?(pickable_devcontainers.first&.path)) || ""
  end

  def pickable_devcontainers
    return @pickable_devcontainers if @pickable_devcontainers.present?

    @pickable_devcontainers = Codespaces::DevContainer.list_dev_containers(repository, initial_branch_ref&.target_oid)
  end

  private

  attr_reader :repository, :initial_branch_ref
end
