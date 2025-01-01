module DependencyGraph::ObjectModel
  # Adapter for returning manifests to graphql
  # Note this does not inherit from AbstractManifest but rather wraps its
  # subclasses. This can be removed once we stop using graphql to show
  # dependencies on dotcom.
  class BaseGraphqlManifest
    attr :id

    def initialize(id, repository_id, manifest)
      @id = id
      @repository_id = repository_id
      @manifest = manifest
    end

    def github_repository_id
      @repository_id
    end

    def manifest_type
      0 # unknown manifest
    end

    def has_revisions?
      false
    end

    def vendored?
      false
    end

    # `#dependencies` will be called by GraphQL to get dependencies for a manifest
    # query. This method fetches dependencies either from the wrapping manifest or by
    # calling DGP, depending on the manifest type. It then queries the local database
    # to get package information.
    def dependencies
      deps = fetch_dependencies

      # return early if there are no dependencies
      return deps if deps.empty?

      # Snapshots doesn't come with package metadata so we look it up locally
      # Create a two level hash to look up packages by the package manager and package name
      by_manager = deps.group_by { |d| d.package_manager }
      matching_packages = by_manager.reduce({}) do |h, (manager, deps)|
        h[manager] = Package.where(package_manager: manager, name: [deps.map(&:package_name)]).to_h do |p|
          [p.name.downcase, p]
        end
        h
      end

      # generate (package_manager, package_name, version) tuples for all the
      # dependencies so we can query PackageReleases for licenses
      ds = deps.map { |d| [d.package_manager.to_i, d.package_name, d.requirements.exact_version] }

      # generate a query for all dependencies: `(pma, name, version) IN ((dep1),(dep2)...)`
      placeholders = Array.new(ds.length, "(?, ?, ?)").join(",")
      package_releases = PackageRelease
        .select("#{PackageRelease.table_name}.*, EXISTS (SELECT 1 FROM #{PackageDependency.table_name} specs WHERE specs.dependent_id = id LIMIT 1) AS has_dependencies")
        .where("(package_manager, package_name, name) IN (#{placeholders})", *ds.flatten)

      # create a table of `key => license` rows. `key` is a unique
      # release identifier.
      releases = {}
      package_releases.each do |rel|
        key = dependency_key(rel.package_manager, rel.package_name, rel.name)
        releases[key] = {
          license: rel.license,
          has_dependencies: rel.has_dependencies
        }
      end

      deps.each do |dependency|
        package = matching_packages[dependency.package_manager][dependency.package_name.downcase]
        next unless package

        key = dependency_key(dependency.package_manager, dependency.package_name, dependency.requirements.exact_version)
        dependency.license = releases.dig(key, :license) # won't set a license if we don't have one
        dependency.has_dependencies = releases.dig(key, :has_dependencies) || false
        dependency.package_github_repository_id = package.github_repository_id
        dependency.package_github_repository_id_certainty = package.repository_id_certainty
        dependency.package_label = package.label
        dependency.package_id = package.id
      end
      deps
    end

    # This method should be overridden by subclasses to fetch dependencies
    def fetch_dependencies
      []
    end

    private

    # returns a composite key based on the dependency metadata
    def dependency_key(ecosystem, name, version)
      "#{ecosystem}-#{name}-#{version}"
    end

    def ds_arbitrary_ecosystem_enabled?(repository_id)
      if defined?(@ds_arbitrary_ecosystem_enabled)
        return @ds_arbitrary_ecosystem_enabled
      end
      @ds_arbitrary_ecosystem_enabled = DependencyGraph.flipper[:dependency_graph_snapshot_arbitrary_ecosystems].enabled?(FeatureFlags::Actor::Repository.new(repository_id))
    end
  end
end
