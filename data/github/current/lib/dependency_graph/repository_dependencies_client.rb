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
                                        enable_preview_ecosystems: false)
      rpc_request = {
        sha: sha,
        include_vulnerabilities: include_vulnerabilities,
        include_internal_snapshots: include_internal_snapshots,
        enable_preview_ecosystems: enable_preview_ecosystems,
        repository_id: repository_id,
        owner_id: owner_id,
        max_static_manifests: max_static_manifests
      }

      rpc(:GetDependenciesForRepository, rpc_request)
    end

    def search_dependencies_for_repository(repository_id:, page:, per_page:, query:, dependabot_alerts:, preview_enabled: false)
      rpc_request = {
        repository_id: repository_id,
        page: page,
        per_page: per_page,
        query: query,
        dependabot_alerts: dependabot_alerts,
        preview_enabled: preview_enabled
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
      base_purl = "pkg:#{purl_type}/#{vulnerable_version_range.affects}"
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
  end
end
