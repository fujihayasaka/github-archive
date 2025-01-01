# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client"
require "dependency_graph/base_twirp_client_handler"

module DependencyGraph
  class RepositoryManifestsProvider
    def has_manifests(repository_id:, only_static_manifests: false)
      client_handler do
        response = client.has_manifests(
          repository_id: repository_id,
          only_static_manifests: only_static_manifests
        )

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid Has Manifests response" if response.nil?

        {
          status_code: 200,
          response: response,
          errors: nil
        }
      end
    end

    private

    def client
      @client ||= DependencyGraph::RepositoryDependenciesClient.new(request_timeout_seconds: 10)
    end

    def client_handler(&block)
      DependencyGraph::BaseTwirpClientHandler.client_handler({ class: "DependencyGraph::RepositoryManifestsProvider" }, false, block)
    end
  end
end
