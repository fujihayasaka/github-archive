# typed: true
# frozen_string_literal: true

# Public: Domain object to wrap dependency graph API `Manifest` type
module DependencyGraph
  class Manifest
    include DependencyGraph::Alerting::AlertableManifest
    include GitHub::Relay::GlobalIdentification

    SUPERSEDED_BY = {
      "gemfile" => ["gemfile_lock"],
      "package_json" => %w[package_lock_json yarn_lock],
      "pipenv" => ["pipenv_lock"],
      "composer_json" => ["composer_lock"],
      "pyproject_toml" => ["poetry_lock"],
      "cargo_toml" => ["cargo_lock"],
      "pubspec_yaml" => ["pubspec_lock"],
    }

    EXCEEDS_MAX_SIZE = :exceeds_max_size
    SPONSORABLE_BATCH_SIZE = 500

    def self.wrap(manifests, dependencies_filter = {})
      manifests.map { |attrs| new(attrs["node"], dependencies_filter) }
    end

    def self.exceeds_max_size(attrs)
      new(attrs.merge("error" => EXCEEDS_MAX_SIZE))
    end

    # Helper method to create new instances based off of Twirp output
    # from the DependencyGraph::RepositoryDependenciesProvider endpoint.
    #
    # Returns DependencyGraph::Manifest
    def self.new_from_twirp(twirp_manifest, repo_id:)
      package_manager = twirp_manifest.package_manager.to_s.gsub("PACKAGE_MANAGER_", "")

      # The package manager name in our graphql contract is "GO", but our twirp
      # API kindly uses "GOMOD"
      if package_manager == "GOMOD"
        package_manager = "GO"
      end

      dependencies = twirp_manifest.dependencies.map do |twirp_dependency|
        {
          node: {
            packageName: twirp_dependency.name,
            packageManager: package_manager,
            requirements: twirp_dependency.requirements,
            scope: twirp_dependency.scope,
            relationship: self.from_twirp_relationship(twirp_dependency.relationship),
            vulnerableVersionRanges: {
              edges: twirp_dependency.vulnerable_version_ranges.map do |twirp_vvr|
                {
                  isContained: twirp_vvr.is_contained,
                  node: {
                    githubId: twirp_vvr.github_id
                  }
                }
              end
            }
          }
        }
      end

      path = File.dirname(twirp_manifest.file_path)
      # If path is at the root of the repository, use an empty string to match current behavior.
      path = "" if ["/", "."].include?(path)

      self.new({
        repositoryId: repo_id,
        manifestType: twirp_manifest.type,
        filename: File.basename(twirp_manifest.file_path),
        path: path,
        isVendored: twirp_manifest.is_vendored.nil? ? false : twirp_manifest.is_vendored.value,
        dependencies: { edges: dependencies }.with_indifferent_access,
        dependenciesCount: dependencies.count,
        name: twirp_manifest.name,
        source: twirp_manifest.source,
      }.with_indifferent_access)
    end

    # Public: Get the sponsorable users and orgs (that is, those with a public GitHub Sponsors profile) who represent
    # any of the dependency repositories in the given manifests.
    #
    # Returns a Set of User and Organization records.
    def self.dependency_sponsorables_from(manifests)
      sponsorables = Set.new
      return sponsorables unless GitHub.sponsors_enabled?

      repository_ids = manifests.map { |manifest| manifest.dependency_repository_ids }.reduce(:+).to_a
      repository_ids.each_slice(SPONSORABLE_BATCH_SIZE) do |dependency_repo_ids|
        repo_sponsorables = RepositorySponsorable.for_repository(dependency_repo_ids).includes(:sponsorable)
          .distinct.select(:sponsorable_id)
        sponsorables.merge(repo_sponsorables.map(&:sponsorable).to_set)
      end

      sponsorables
    end

    def self.from_twirp_relationship(relationship)
      case relationship
      when :RELATIONSHIP_DIRECT
        "direct"
      when :RELATIONSHIP_TRANSITIVE
        "transitive"
      else
        "unknown"
      end
    end

    def initialize(attrs, dependencies_filter = {})
      @attrs = attrs
      @dependencies_filter = dependencies_filter
    end

    def platform_type_name
      "DependencyGraphManifest"
    end

    def global_id
      "#{repository_id}:#{id}"
    end

    def repository_id
      attrs["repositoryId"]
    end

    def id
      attrs["id"]
    end

    def source
      attrs["source"]
    end

    def snapshot_detector_name
      attrs["snapshotDetectorName"]
    end

    def snapshot_scanned
      attrs["snapshotScanned"].try { |x| Time.iso8601(x) }
    end

    def manifest_type
      attrs["manifestType"]
    end

    def basename
      attrs["filename"]
    end

    def name
      attrs["name"]
    end

    # Returns a "logical path" to the manifest. For most manifests, this is the
    # full path to the file in the repository.
    # For manifests that come from snapshots, which did not submit a path,
    # this will be the manifest name.
    sig { override.returns(String) }
    def logical_path
      if source == "snapshots" && path.blank? && basename.blank?
        # Some snapshots have a manifest with no path or filename, just a name.
        # In those cases, we use the name as the path to the manifest.
        name
      else
        # In all other cases, we still want to use the filename.
        filename
      end
    end

    # Normalize the logical path by removing leading characters
    # Some examples:
    # - ./package.json -> package.json
    # - /path/to/package.json -> path/to/package.json
    #
    # Note: filename also removes a leading slash, and we may want to
    # combine these
    sig { override.returns(String) }
    def normalized_path
      # Regex: ^ is the start of the string, followed by either "./" or "/"
      logical_path.sub(/^(\.\/|\/)+/, "")
    end

    def path
      attrs["path"]
    end

    sig { override.returns(T::Boolean) }
    def vendored?
      !!attrs["isVendored"]
    end

    def filename
      pathname = Pathname.new(path).join(basename).to_s
      pathname.start_with?("/") ? pathname[1..-1] : pathname
    end

    def depth
      filename.split("/").count
    end

    def dependencies_count
      attrs["dependenciesCount"] || attrs.dig("dependencies", "totalCount") || 0
    end

    def dependencies_page_info
      {
        start_cursor: attrs.dig("dependencies", "pageInfo", "startCursor"),
        end_cursor: attrs.dig("dependencies", "pageInfo", "endCursor"),
        has_next_page: attrs.dig("dependencies", "pageInfo", "hasNextPage"),
        has_previous_page: attrs.dig("dependencies", "pageInfo", "hasPreviousPage"),
      }
    end

    def dependencies_filter
      @dependencies_filter
    end

    sig { override.returns(T::Array[DependencyGraph::Alerting::AlertableDependency]) }
    def dependencies
      @dependencies ||= Dependency.wrap(attrs.dig("dependencies", "edges"), manifest: self)
    end

    def dependency_repository_ids
      dependencies.map(&:repository_id).to_set
    end

    def async_repository
      Platform::Loaders::ActiveRecord.load(::Repository, repository_id)
    end

    def to_json
      attrs.to_json
    end
    alias_method :as_json, :to_json

    def ==(other)
      other.class == self.class && other.attrs == self.attrs
    end

    sig { override.params(other: T.untyped).returns(T.nilable(T::Boolean)) }
    def supersedes?(other)
      other.is_a?(Manifest) && other.path == path && SUPERSEDED_BY[other.manifest_type]&.include?(manifest_type)
    end

    def exceeds_max_size?
      error == EXCEEDS_MAX_SIZE
    end

    def error
      attrs["error"]
    end

    def parseable?
      error.blank?
    end

    protected

    attr_reader :attrs
  end
end
