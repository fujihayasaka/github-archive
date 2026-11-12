module Snapshots
  # This class represents a flattened set of all the dependencies in all the
  # supplied manifests (as ManifestDependency objects).
  # It's basically a wrapper around Set, but it also converts between Dependency
  # and ManifestDependency objects.
  class ManifestDependencySet
    attr_accessor :dependencies

    # Returns a map of manifest_path -> [Snapshots::Dependency]
    def to_manifests
      @dependencies.classify(&:manifest_path).transform_values { |s| s.map(&:to_dependency) }
    end

    def -(other)
      ret = Snapshots::ManifestDependencySet.new
      ret.dependencies = @dependencies - other.dependencies
      ret
    end

    def collect
      @dependencies
    end

    def union(other)
      @dependencies.union(other.dependencies)
    end

    def difference(other)
      @dependencies.difference(other)
    end

    private def snapshot_dependencies(snapshot)
      dependencies = Set.new
      snapshot.manifests.each do |m|
        m.dependencies.each do |dep|
          dependencies.add(
            Snapshots::ManifestDependency.new(
              manifest_path: m.path,
              name: dep.name,
              version: dep.version,
              scope: dep.scope
            )
          )
        end
      end

      dependencies
    end

    private def dependency_snapshot_dependencies(dependency_snapshot)
      dependencies = Set.new
      dependency_snapshot.manifests.each do |manifest_path, content|
        # Twirp will have a json blob not a symbol
        graph = content[:graph] || content["graph"]

        graph.each do |dep_purl, dep_content|
          scope = dep_content[:scope] || dep_content["scope"]

          dependencies.add(
            Snapshots::ManifestDependency.new(
              manifest_path: manifest_path,
              scope: scope,
              purl: PackageUrls::PackageUrl.from_purl(purl: dep_purl)
            )
          )
        end
      end

      dependencies
    end

    def initialize(snapshot = nil)
      @dependencies = Set.new

      # when doing diffing we create empty sets (no snapshot)
      return unless snapshot.present?

      @dependencies = snapshot_dependencies(snapshot)
    end
  end

  # A ManifestDependency is similar to a Snapshots::Dependency, but it
  # also knows which manifest it came from. This lets us treat all the
  # dependencies from a snapshot, however many manifests it has, as a single
  # flat set (see ManifestDependencySet).
  class ManifestDependency
    attr_reader :manifest_path, :name, :version, :scope, :purl

    def to_dependency
      Snapshots::Dependency.new(
        name: name,
        version: version,
        scope: scope,
        purl: purl
      )
    end

    def initialize(manifest_path:, name: nil, version: nil, scope:, purl: nil)
      @manifest_path = manifest_path
      @name = purl&.name|| name
      @version = purl&.version || version
      @scope = scope
      @purl = purl
    end

    def key
      "#{manifest_path}#{name}#{version}#{scope}"
    end

    def hash
      key.hash
    end

    def eql?(other)
      hash == other.hash
    end
  end
end
