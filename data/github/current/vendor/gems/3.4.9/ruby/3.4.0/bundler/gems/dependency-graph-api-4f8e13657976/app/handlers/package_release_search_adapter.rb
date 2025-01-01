# HOTFIX: Adapt dependency versions to store package release idioms
#
# Dependency Graph typically uses generic, normalised dependency versions
# but our PackageRelease table follows ecosystem-specific conventions in
# some cases which means that these do not always compare cleanly.
#
# This method makes a best effort to adapt the incoming version to match
# the PackageRelease format.
#
# See:
# - https://github.com/github/dependency-graph/issues/7300
# - https://github.com/github/dependency-graph/discussions/2901
module PackageReleaseSearchAdapter
  def self.adapted_dependency_version(package_manager_type, package_version)
    return adapted_gomod_version(package_version) if package_manager_type == Types::PackageManager[:go]
    package_version
  end

  private_class_method def self.adapted_gomod_version(package_version)
    return package_version unless package_version.is_a? String
    return package_version if package_version.start_with?("v")

    "v" + package_version
  end
end
