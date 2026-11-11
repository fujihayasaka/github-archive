# typed: true
# frozen_string_literal: true

class Registry::StorageUsage
  def initialize(owner:, repository:)
    @owner = owner
    @repository = repository
  end

  def billing_actions_usage
    0
  end

  def billing_combined_usage
    0
  end

  def billing_aggregated_usage
    0
  end

  def billing_pending_usage
    0
  end

  def billing_packages_usage
    0
  end

  def billing_packages_v2_usage
    0
  end

  def packages_usage
    return 0 unless @repository.private?

    @repository
      .packages
      .joins(package_versions: [:package_files])
      .merge(::Registry::PackageVersion.not_deleted.unmigrated)
      .sum("package_files.size")
  end

  def packages_non_docker_usage
    return 0 unless @repository.private?

    @repository
      .packages
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
