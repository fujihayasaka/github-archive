require_relative "ds_api_client"

module DependencyGraphAPI::DependencySnapshotsAPI
  class DependenciesClient
    include DSAPIClient

    def initialize(use_json: false)
      @use_json = use_json
    end

    # get_dependencies_for_repository: retrieve the "default" (usually, latest on
    # default branch) snapshot by its GitHub repository id.
    #
    # repository_id: GitHub repository ID (unsigned nonzero integer)
    #
    # include_internal_snapshots: DEPRECATED.
    #
    # include_root_ancestors: determines whether to request root ancestors from ds-api
    #
    # relationship_filter: optional. Should be ether :RELATIONSHIP_UNKNOWN, :RELATIONSHIP_INCONCLUSIVE, :RELATIONSHIP_DIRECT, or :RELATIONSHIP_INDIRECT,
    #   as defined in proto/twirp/v1/dependency_graph_api.proto
    def get_dependencies_for_repository(repository_id, include_internal_snapshots: false, include_root_ancestors: false, relationship_filter: nil)
      case relationship_filter
      when :RELATIONSHIP_UNKNOWN
        relationship_filter = :UNKNOWN
      when :RELATIONSHIP_INCONCLUSIVE
        relationship_filter = :UNKNOWN
      when :RELATIONSHIP_DIRECT
        relationship_filter = :DIRECT
      when :RELATIONSHIP_INDIRECT
        relationship_filter = :INDIRECT
      end

      request = Github::DependencySnapshotsApi::GetDependenciesForRepositoryRequest.new(
        repository_id: repository_id,
        include_internal_snapshots: include_internal_snapshots,
        include_root_ancestors: include_root_ancestors,
        relationship_filter: relationship_filter
      )

      client.get_dependencies_for_repository(request)
    end

    # repositories_containing_dependency: get a list of repository IDs that contain
    # at least one dependency matching the criteria in the request.
    #
    # base_purl: package url (purl) of the dependency in the string format of
    # "scheme:type/namespace/name" with optional namespace and excludes @version?qualifiers#subpath
    # @example: "pkg:/npm/%40actions/core"
    #
    # version_range: a semver constraint in the string format, e.g. "5.0.0", ">1.2.3" or "<= 1.2.3, >= 1.4".
    def repositories_containing_dependency(base_purl, version_range)
      request = Github::DependencySnapshotsApi::RepositoriesContainingDependencyRequest.new(
        base_purl: base_purl,
        version_range: version_range)

      client.repositories_containing_dependency(request)
    end

    def has_manifests(repository_id)
      request = Github::DependencySnapshotsApi::HasManifestsRequest.new(
        repository_id: repository_id,
      )

      client.has_manifests(request)
    end

    def client
      content_type = @use_json ? Twirp::Encoding::JSON : nil
      @client ||= Github::DependencySnapshotsApi::DependenciesServiceClient.new(connection, content_type: content_type)
    end
  end
end
