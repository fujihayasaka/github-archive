# typed: strict
# frozen_string_literal: true

# Background job that updates the `deployable` and `deployed` system property values
# for a repository in the `repository_system_property_values` table.
#
# This job is enqueued when storage records or deployment records are created, updated, or deleted.
# It queries the current state of the repository's artifact records and writes the appropriate
# system property value for all properties:
# - "true" if at least one active record exists
# - "false" if records exist but none are active (all soft-deleted/decommissioned)
# - empty string ("") if no records exist at all (removes the row from the table)
#
# @see ArtifactRegistry::Domain::StorageRecords#repository_deployable?
# @see ArtifactRegistry::Domain::DeploymentRecords#repository_deployed?
class UpdateRepositoryDeploymentPropertiesJob < ApplicationJob
  queue_as :repository_system_properties_update

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  # We write to Repositories in a connected_to(:writing) block but we declare
  # it as a replica here so we wait for replication lag on this cluster when reading
  use_replicas ApplicationRecord::Repositories,
    ApplicationRecord::ArtifactRegistry,
    ApplicationRecord::Mysql1

  sig { params(repository_id: Integer).void }
  def perform(repository_id)
    repository = Repository.find_by(id: repository_id)
    if repository.nil?
      GitHub.logger.info(
        "Repository not found for repository system properties update",
        "gh.repo.id" => repository_id,
      )
      return
    end

    owner = repository.owner
    unless owner&.organization?
      GitHub.logger.info(
        "Repository owner is not an organization, skipping system property update",
        "gh.repo.id" => repository_id,
      )
      return
    end

    unless Repositories.domain.custom_properties.system_properties_enabled?(T.cast(owner, Organization))
      GitHub.logger.info(
        "Custom properties system properties disabled for repository owner, skipping system property update",
        "gh.repo.id" => repository_id,
      )
      return
    end

    deployable, deployed = compute_deployment_values(repository.id)

    update_property(repository, "deployable", deployable)
    update_property(repository, "deployed", deployed)
  end

  private

  sig { params(repository: Repository, property_name: String, value: T.nilable(String)).void }
  def update_property(repository, property_name, value)
    GitHub.logger.info(
      "Updating repository system property for repository",
      "gh.repo.id" => repository.id,
      "gh.property_name" => property_name,
      "gh.property_value" => value.inspect,
    )

    with_write do
      Repositories.domain.custom_properties.set_system_properties_for(
        [repository],
        property_name,
        value,
        value_type: "true_false"
      )
    end
  end

  # Returns an array of [deployable_value, deployed_value] for the given repository ID.
  sig { params(repository_id: Integer).returns([T.nilable(String), T.nilable(String)]) }
  def compute_deployment_values(repository_id)
    # First check to see if the repository is deployed.
    # If it is, we know the repo is both deployable and deployed, so we can skip the second check.
    deployed = ArtifactRegistry.domain.deployment_records.repository_deployed?(repository_id)
    return %w[true true] if deployed

    # If the repository is not deployed, check if it is deployable.
    # If it is, we can return "true" for deployable and "false" for deployed.
    deployable = ArtifactRegistry.domain.storage_records.repository_deployable?(repository_id)
    return %w[true false] if deployable

    # If the repo was neither deployable nor deployed, return nil for both values
    # Artifact metadata is either not present or soft-deleted when there is no active storage or deployment record
    [nil, nil]
  end
end
