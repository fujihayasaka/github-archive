# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client"

module DependencyGraph
  class RepositorySBOMClient < DependencyGraph::BaseTwirpClient
    def get_repository_sbom(repository_id:, repository_name:, sha:, repository_license:)
      rpc_request = {
        repository_id: repository_id,
        sha: sha,
        namespace_base: GitHub.url,
        repository_name: repository_name,
        repository_license: repository_license,
      }

      rpc(:GetRepositorySBOM, rpc_request)
    end

    private

    def twirp_class
      DependencyGraphAPI::V1::RepositorySBOMClient
    end

    def twirp_url_namespace
      "repository-sbom"
    end
  end
end
