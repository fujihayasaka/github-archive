# typed: true
# frozen_string_literal: true

# Acts as a factory class to produce correctly configured RepositoryDependencyUpdate
# objects for the highest required version to resolve alerts for a given dependency
#
# This class is considered internal to RepositoryDependencyUpdate, for the public
# interface, see: RepositoryDependencyUpdate::request_for_dependency
class RepositoryDependencyUpdate::DependencyResolver
  attr_reader :repository, :manifest_path, :package_name, :trigger

  def initialize(repository:, manifest_path:, package_name:, trigger:)
    @repository = repository
    @manifest_path = manifest_path
    @package_name = package_name
    @trigger = trigger.to_s
  end

  def create_update
    validate_trigger_type

    suggested_fix = RepositoryVulnerabilityAlert::SuggestedFix.new(open_alerts)

    return false unless suggested_fix.candidate_alert

    RepositoryDependencyUpdate::AlertResolver.new(suggested_fix.candidate_alert,
                                                  trigger: trigger).create_update
  end

  private

  def open_alerts
    repository.repository_vulnerability_alerts
              .for_manifest_and_package(manifest_path: manifest_path, package_name: package_name)
              .preload(:vulnerable_version_range)
              .open
  end

  def validate_trigger_type
    raise ArgumentError, "The 'dry_run' trigger is no longer supported"  if trigger == "dry_run"
    raise ArgumentError, "Unknown trigger '#{trigger}'" unless RepositoryDependencyUpdate.trigger_types.keys.include?(trigger)
  end
end
