# frozen_string_literal: true

class UpdatedDependenciesMetadataPresenter
  def initialize(updated_dependencies:, security_updates_only:, dependency_group:)
    @updated_dependencies = updated_dependencies
    @security_updates_only = security_updates_only
    @dependency_group = dependency_group
  end

  def metadata
    { "updated-dependencies" => updated_dependencies_metadata }
  end

  private

  attr_reader :updated_dependencies, :security_updates_only, :dependency_group

  def updated_dependencies_metadata
    updated_dependencies.map do |updated_dependency|
      dependency_spec = updated_dependency.production? ? "production" : "development"
      dependency_type = updated_dependency.requirements.any? ? "direct:#{dependency_spec}" : "indirect"
      update_type = UpdatedDependencyPresenter.new(updated_dependency: updated_dependency).update_type
      metadata = {
        "dependency-name" => updated_dependency.name,
        "dependency-version" => updated_dependency.version,
        "dependency-type" => dependency_type,
      }
      # NOTE: Exclude update type for security updates until we decide we want
      # to expose it to read-only users. When we add it, align with planned
      # ignore syntax: `security-update:severity-x`
      metadata["update-type"] = "version-update:#{update_type}" if update_type && !security_updates_only
      metadata["dependency-group"] = dependency_group&.name unless dependency_group.nil?
      metadata
    end
  end
end
