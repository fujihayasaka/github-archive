require_relative "../../../lib/dependency_graph/object_model/dgp_graphql_manifest"
require_relative "../../../lib/dependency_graph/object_model/ds_graphql_manifest"
require_relative "../../../lib/dependency_graph/object_model/ds_api_manifest"
require_relative "../../../lib/dependency_graph/object_model/ds_graphql_dependency"
require "dependency_snapshots_api/dependencies_client"
require "dependency-graph-platform/graphql_resolver_client"

module Queries
  class ManifestsQuery
    def initialize(repository_ids:, **options)
      # Currently, this is never called with more than one repository ID
      @repository_ids = repository_ids
      @options = options
      @dependencies_client = DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient.new
      @dgp_graphql_client = DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient.new
      @dgp_available = !::DependencyGraphAPI.enterprise?
    end

    def manifests
      return @manifests if defined?(@manifests)

      unless with_snapshots? && DependencyGraphAPI.snapshots_enabled?
        @manifests = static_manifests
        return @manifests
      end

      # Create a hash to store manifests by their unique path+filename
      manifests_by_path = {}

      # Add snapshot_manifests first, as they take precedence
      snapshot_manifests.each do |manifest|
        key = DependencyGraph::ObjectModel::AbstractManifest.normalize_manifest_path("#{manifest.path}/#{manifest.filename}")
        manifests_by_path[key] = manifest
      end

      # Add static manifests, but only if the path+filename is not already in the hash
      static_manifests.each do |manifest|
        key = DependencyGraph::ObjectModel::AbstractManifest.normalize_manifest_path("#{manifest.path}/#{manifest.filename}")
        manifests_by_path[key] ||= manifest
      end

      # Return the combined manifests as an array
      @manifests = manifests_by_path.values
      return @manifests
    end

    # Return all static manifests, including DGP manifests if the feature is enabled
    def static_manifests
      local_manifests + dgp_manifests
    end

    # Return the manifests found in the DG-API database
    def local_manifests
      # If the package_manager filter is set and is one of DGP package managers, we don't need to query the database
      if package_manager && package_managers_from_dgp.include?(package_manager)
        return []
      end

      scope = Manifest.with_github_repository_id(repository_ids)
      scope = scope.where(id: options[:ids]) if options[:ids]
      if DependencyGraph.use_normalized_tables?
        scope = scope.with_entries if with_dependencies?
      else
        scope = scope.with_dependencies if with_dependencies?
      end
      scope = scope.of_type(manifest_types) if type_restriction?
      scope = scope.where(name: options[:package_name]) if options[:package_name]

      # Limit the scope to the package manager set in the request
      if package_manager
        scope = scope.for_package_manager(package_manager)
      # Otherwise, get all package managers but exclude the ones from DGP
      elsif package_managers_from_dgp.any?
        scope = scope.exclude_package_managers(package_managers_from_dgp)
      end

      scope = scope.least_nested_first.alphabetized
      scope.reject(&:unsupported_vendored_manifest?)
    end

    # Return the manifests found in DGP
    def dgp_manifests
      return [] unless manifests_from_dgp?
      @dgp_manifests ||= repository_ids.reduce([]) do |result, id|
        response = dgp_manifests_for_repository(id)
        result += response.map do |manifest|
          DependencyGraph::ObjectModel::DGPGraphqlManifest.new(manifest)
        end
      end
    end

    def snapshot_manifests
      return @snapshot_manifests if defined?(@snapshot_manifests)

      include_internal_snapshots = options[:include_internal_snapshots] || false
      manifests = repository_ids.reduce([]) do |result, id|
        response = dependencies_client.get_dependencies_for_repository(id, include_internal_snapshots: include_internal_snapshots)
        if response.error.present?
          DependencyGraph.logger.error("Outbound call to d-s-api failed",
                                       "exception.message" => response.error.msg[..500])
          return Twirp::Error.internal("An unexpected error occurred during snapshot retrieval")
        end

        converted_manifests = DependencyGraph::ObjectModel::DSAPIManifest.from_api_manifests(response.data.all_manifests)
        result += converted_manifests.map do |m|
          s = response.data.snapshots[m.snapshot_id]
          DependencyGraph::ObjectModel::DSGraphqlManifest.new(m, s, id)
        end
      end

      if options[:ids]
        @snapshot_manifests = manifests.filter { |m| options[:ids].include?(m.id) }
      else
        @snapshot_manifests = manifests
      end
    end

    # Return the count of manifests
    # Note that the implementation actually loads the manifests. We decided
    # not to optimize this for now. The local implementation could conceivably
    # be changed to use a count query, but it would take more effort to
    # ensure that the count properly adjusts for duplicates that are removed.
    def total_count_for_repository
      return manifests.count
    end

    private

    attr_reader :repository_ids, :options, :dependencies_client, :dgp_graphql_client, :dgp_available

    def with_dependencies?
      options[:with_dependencies] || false
    end

    def with_snapshots?
      if options[:with_snapshots].nil?
        true
      else
        options[:with_snapshots]
      end
    end

    def manifest_types
      options[:manifest_types]
    end

    def package_manager
      options[:package_manager]
    end

    def package_managers_from_dgp
      pms = manifests_from_dgp? ? Types::PackageManager.supported_by_dgp : []
      # Intersection is used to make sure we only return the package manager that is requested by the user, if specified
      pms &= [package_manager] if package_manager
      pms
    end

    def type_restriction?
      options.has_key?(:manifest_types)
    end

    def dgp_manifests_for_repository(repository_id)
      return [] if package_managers_from_dgp.empty?

      response = dgp_graphql_client.get_manifests_for_repository(
        repository_id: repository_id,
        manifest_ids: options[:ids] || [],
        with_dependencies: with_dependencies?,
        ecosystems: package_managers_from_dgp.map { |pm| pm.dgp_ecosystem.to_sym },
      )

      if response.error.present?
        DependencyGraph.logger.error("Outbound call to dgp failed",
                                     "exception.message" => response.error.msg[..500])
        return Twirp::Error.internal("An unexpected error occurred during dgp manifests retrieval")
      end

      response.data.manifests
    end

    def manifests_from_dgp?
      # We should never have more than one repository, and if we do, then it's not a public API call
      return false if repository_ids.count != 1
      dgp_available
    end
  end
end
