# frozen_string_literal: true

# TODO: Move this to dependabot-core once this is stabilised in the wild. The
# mapping is (almost) inverse to the generated ignore conditions from
# update-type's in core's IgnoreCondition class.
class UpdatedDependencyPresenter
  attr_reader :updated_dependency

  def initialize(updated_dependency:)
    @updated_dependency = updated_dependency
  end

  def update_type
    return nil unless version_class_compatible?

    case update_precision
    when 0
      nil
    when 1
      "semver-major"
    when 2
      "semver-minor"
    else
      "semver-patch"
    end
  end

  private

  def version_class_compatible?
    previous_version &&
      version_class.correct?(previous_version) &&
      version &&
      version_class.correct?(version)
  end

  def update_precision
    version_parts = version.split(".")
    version_parts.fill("0", version_parts.length..3)
    previous_version_parts = previous_version.split(".")
    previous_version_parts.fill("0", previous_version_parts.length..3)
    return 0 unless version_parts.first(2).all? { |part| part.to_i.to_s == part }
    return 0 unless previous_version_parts.first(2).all? { |part| part.to_i.to_s == part }
    return 1 if version_parts[0] != previous_version_parts[0]
    return 2 if version_parts[1] != previous_version_parts[1]

    3
  end

  def version
    updated_dependency.version
  end

  def previous_version
    updated_dependency.previous_version
  end

  def version_class
    Dependabot::Utils.version_class_for_package_manager(updated_dependency.package_manager)
  end

  def requirement_class
    Dependabot::Utils.requirement_class_for_package_manager(updated_dependency.package_manager)
  end
end
