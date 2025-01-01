# typed: true
# frozen_string_literal: true

class Registry::StorageUsage
  def initialize(owner:, repository:)
    @owner = owner
    @repository = repository
  end

  def billing_actions_usage
    query = ::Billing::SharedStorage::ArtifactEvent
      .private_visibility
      .where(owner_id: @repository.owner_id, repository_id: @repository.id)
      .actions_source

    summarize_artifact_events(query)
  end

  def billing_combined_usage
    billing_aggregated_usage + billing_pending_usage
  end

  def billing_aggregated_usage
    ActiveRecord::Base.connected_to(role: :reading) do
      ::Billing::SharedStorage::CurrentUsage
        .find_by(owner_id: @repository.owner_id, repository_id: @repository.id)
        &.aggregate_size_in_bytes.to_i
    end
  end

  def billing_pending_usage
    query = ::Billing::SharedStorage::ArtifactEvent
      .private_visibility
      .where(owner_id: @repository.owner_id, repository_id: @repository.id)
      .where(aggregation_id: nil)

    summarize_artifact_events(query)
  end

  def billing_packages_usage
    query = ::Billing::SharedStorage::ArtifactEvent
      .private_visibility
      .where(owner_id: @repository.owner_id, repository_id: @repository.id)
      .gpr_source

    summarize_artifact_events(query)
  end

  def billing_packages_v2_usage
    query = ::Billing::SharedStorage::ArtifactEvent
      .private_visibility
      .where(owner_id: @owner.id)
      .packages_v2_source

    summarize_artifact_events(query)
  end

  def packages_usage
    @repository
      .packages
      .private_scope
      .joins(package_versions: [:package_files])
      .merge(::Registry::PackageVersion.not_deleted.unmigrated)
      .sum("package_files.size")
  end

  def packages_non_docker_usage
    @repository
      .packages
      .private_scope
      .where.not(package_type: :docker)
      .joins(package_versions: [:package_files])
      .merge(::Registry::PackageVersion.not_deleted)
      .sum("package_files.size")
  end

  def packages_v2_usage
    PackageRegistry::Twirp.metadata_client
      .get_eco_namespace_storage_utilization(namespace: @owner.name)
      .total_storage_bytes
  end

  private

  def summarize_artifact_events(artifact_event_query)
    result = artifact_event_query.sum(<<~SQL)
        CASE event_type
        WHEN 'add' then size_in_bytes
        WHEN 'remove' then -1 * size_in_bytes
        ELSE 0
        END
      SQL

    result.to_i
  end
end
