# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client"

module DependencyGraph
  class RepositoryDependenciesClient < DependencyGraph::BaseTwirpClient
    def initialize(request_timeout_seconds: 120)
      # request_timeout for these calls should be a little higher. The backend is making a few different calls to spokes and potentially parsing
      # many manifests. This was done because we had a high number of timeout events at the 10s level.
      super(request_timeout_seconds: request_timeout_seconds)
    end

    def get_dependencies_for_repository(sha:, repository_id:, owner_id:, max_static_manifests: 20,
                                        include_vulnerabilities: true, include_internal_snapshots: false,
                                        enable_preview_ecosystems: false, exclude_ecosystems: [])
      rpc_request = {
        sha: sha,
        include_vulnerabilities: include_vulnerabilities,
        include_internal_snapshots: include_internal_snapshots,
        enable_preview_ecosystems: enable_preview_ecosystems,
        repository_id: repository_id,
        owner_id: owner_id,
        max_static_manifests: max_static_manifests,
        exclude_ecosystems: exclude_ecosystems,
      }

      rpc(:GetDependenciesForRepository, rpc_request)
    end

    def search_dependencies_for_repository(repository_id:, page:, per_page:, query:, dependabot_alerts:, preview_enabled: false, relationship_filter:, ecosystem_filter:)
      rpc_request = {
        repository_id: repository_id,
        page: page,
        per_page: per_page,
        query: query,
        dependabot_alerts: dependabot_alerts,
        preview_enabled: preview_enabled,
        relationship_filter: relationship_filter,
        ecosystem_filter: ecosystem_filter
      }

      rpc(:SearchDependenciesForRepository, rpc_request)
    end

    def has_manifests(repository_id:, only_static_manifests: false)
      rpc_request = {
        repository_id: repository_id,
        only_static_manifests: only_static_manifests
      }

      rpc(:HasManifests, rpc_request)
    end

    # Temporary: the use of the `get_repositories_containing_dependency` endpoint directly in dotcom
    # is a short-term solution to the problem of the dependency-graph-api not being able to
    # return the correct results via our standard GraphQL query. That also applies to get_repositories_containing_vvr.
    def get_repositories_containing_vvr(vulnerable_version_range:)
      base_purl = construct_base_purl(vulnerable_version_range)
      range = vulnerable_version_range.requirements
      get_repositories_containing_dependency(base_purl: base_purl, semver_range: range)
    end

    def get_repositories_containing_dependency(base_purl:, semver_range:)
      rpc_request = {
        base_purl: base_purl,
        version_range: semver_range
      }

      response = rpc(:RepositoriesContainingDependency, rpc_request)
      response.repository_ids.to_a
    end

    private

    def twirp_class
      DependencyGraphAPI::V1::RepositoryDependenciesAPIClient
    end

    def twirp_url_namespace
      "repository-dependencies"
    end

    def construct_base_purl(vulnerable_version_range)
      # For the most part, the package-url type is the same as the ecosystem name, but in these cases
      # it's different.
      #
      # TODO: This could be converted to use AdvisoryDB::Ecosystems.purl_type, but there are several currently
      #       supported ecosystems that use a PURL type that is different than the ecosystem name, moreso than the
      #       three enumerated below. For example, Rust (`cargo`) and GitHub Actions (currently only supported as
      #       `github` but often specified as `github-actions`). See
      #       https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst.
      ecosystem_to_purl_prefix = {
        AdvisoryDB::Ecosystems::RUBYGEMS.name => "gem",
        AdvisoryDB::Ecosystems::PIP.name => "pypi",
        AdvisoryDB::Ecosystems::GO.name => "golang",
      }
      purl_type = ecosystem_to_purl_prefix[vulnerable_version_range.ecosystem] || vulnerable_version_range.ecosystem

      package_name = vulnerable_version_range.affects

      if vulnerable_version_range.ecosystem == AdvisoryDB::Ecosystems::MAVEN.name
        # Maven packages follow the naming convention of `project-group-identifier:artefact-id`, but in purl notation
        # this becomes `project-group-identifier/artefact-id`.
        #
        # In the event of a malformed artefact-id that uses a `/`, anything we do is the in the realms of GIGO, so
        # we favour least action and limit the substitution to only the first occurrence.
        #
        # See: https://maven.apache.org/guides/mini/guide-naming-conventions.html
        package_name = package_name.sub(":", "/")
      end

      "pkg:#{purl_type}/#{package_name}"
    end
  end
end
