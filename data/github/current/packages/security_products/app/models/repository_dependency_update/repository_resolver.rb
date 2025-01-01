# typed: true
# frozen_string_literal: true

# Acts as a factory class to produce correctly configured RepositoryDependencyUpdate
# objects for all open alerts on a given Repository.
#
# This class is considered internal to RepositoryDependencyUpdate, for the public
# interface, see: RepositoryDependencyUpdate::request_for_repository
class RepositoryDependencyUpdate::RepositoryResolver
  attr_reader :repository, :trigger, :dependency_limit

  def initialize(repository, trigger:, dependency_limit: 10)
    @repository = repository
    @trigger = trigger.to_s
    @dependency_limit = dependency_limit
  end

  def create_updates
    validate_trigger_type

    patched_vulnerable_dependencies.map do |vulnerable_dependency|
      RepositoryDependencyUpdate::DependencyResolver.new(repository: repository,
                                                         manifest_path: vulnerable_dependency.vulnerable_manifest_path,
                                                         package_name: vulnerable_dependency.vulnerable_version_range.affects,
                                                         trigger: trigger).create_update
    end.reject(&:blank?)
  end

  private

  def patched_vulnerable_dependencies
    vulnerable_version_range_ids = open_alerts.
      distinct.
      pluck(:vulnerable_version_range_id)
    patched_vulnerable_version_range_ids = VulnerableVersionRange.
      where(id: vulnerable_version_range_ids).
      where.not(fixed_in: nil).
      ids
    open_alerts.
      where(vulnerable_version_range_id: patched_vulnerable_version_range_ids).
      preload(:vulnerable_version_range).
      limit(dependency_limit)
  end

  def open_alerts
    repository.repository_vulnerability_alerts
              .open
              .newest_first
  end

  def validate_trigger_type
    raise ArgumentError, "The 'dry_run' trigger is no longer supported"  if trigger == "dry_run"
    raise ArgumentError, "Unknown trigger '#{trigger}'" unless RepositoryDependencyUpdate.trigger_types.keys.include?(trigger)
  end
end
