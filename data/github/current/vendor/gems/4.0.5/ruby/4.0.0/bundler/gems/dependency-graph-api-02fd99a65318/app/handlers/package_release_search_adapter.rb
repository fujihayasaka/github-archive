# HOTFIX: Adapt dependency versions to store package release idioms
#
# Dependency Graph typically uses generic, normalised dependency versions
# but our PackageRelease table follows ecosystem-specific conventions in
# some cases which means that these do not always compare cleanly.
#
# This method makes a best effort to adapt the incoming version to match
# the PackageRelease format.
#
# For Composer, data is inconsistent (98% without v prefix, 2% with v prefix).
# Callers must query with both add_v_prefix and strip_v_prefix versions explicitly.
#
# See:
# - https://github.com/github/dependency-graph/issues/7300 (Go)
# - https://github.com/github/dependency-graph/issues/7541 (Composer)
# - https://github.com/github/dependency-graph/discussions/2901
module PackageReleaseSearchAdapter

  # Accepts a package manager type and a dependency version as input,
  # and returns an adapted version suitable for querying PackageRelease.
  def self.adapted_dependency_version(package_manager_type, package_version)
    if package_manager_type == Types::PackageManager[:go]
      return add_v_prefix(package_version)
    end
    package_version
  end

  # Accepts a package manager type and a package version as input,
  # and returns an adapted version suitable for querying ManifestPackageVersions and ManifestDependencies.
  def self.adapted_package_version(package_manager_type, package_version)
    if package_manager_type == Types::PackageManager[:go]
      return strip_v_prefix(package_version)
    end
    package_version
  end

  # Returns all possible version tuples for querying PackageRelease.
  # For Composer, returns both with and without v prefix (data is inconsistent).
  # For Go, returns only v-prefixed version.
  # For other package managers, returns original version.
  def self.version_tuples_for_query(package_manager_type, package_version)
    if package_manager_type == Types::PackageManager[:composer]
      # For Composer, data is inconsistent (98% without v, 2% with v)
      # so we try both versions to handle all cases
      with_v = add_v_prefix(package_version)
      without_v = strip_v_prefix(package_version)
      [with_v, without_v].uniq
    else
      [adapted_dependency_version(package_manager_type, package_version)]
    end
  end

  def self.add_v_prefix(package_version)
    return package_version unless package_version.is_a? String
    return package_version if package_version.start_with?("v")

    "v" + package_version
  end

  def self.strip_v_prefix(package_version)
    return package_version unless package_version.is_a? String
    return package_version[1..] if package_version.start_with?("v")
    package_version
  end
end
