# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client"
require "dependency_graph/base_twirp_client_handler"

module DependencyGraph
  class RepositoryDependenciesProvider
    def get_dependencies_for_repository(sha:, repository_id:, owner_id:, max_static_manifests: 20,
                                        enable_preview_ecosystems: false, include_internal_snapshots: false)
      client_handler do
        response = client.get_dependencies_for_repository(
          repository_id: repository_id,
          owner_id: owner_id,
          sha: sha,
          max_static_manifests: max_static_manifests,
          include_internal_snapshots: include_internal_snapshots,
          enable_preview_ecosystems: enable_preview_ecosystems,
        )

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid Get Dependencies For Repository response" if response.nil?

        {
          status_code: 200,
          response: response,
          errors: nil
        }
      end
    end

    def search_dependencies_for_repository(repository_id:, page:, per_page:, query:, dependabot_alerts:, preview_enabled: false, relationship_filter:, ecosystem_filter:)

      client_handler do
        response = client.search_dependencies_for_repository(
          repository_id: repository_id,
          page: page,
          per_page: per_page,
          query: query,
          dependabot_alerts: dependabot_alerts,
          preview_enabled: preview_enabled,
          relationship_filter: relationship_filter,
          ecosystem_filter: ecosystem_filter,
        )

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid Search Dependencies For Repository response" if response.nil?

        {
          status_code: 200,
          response: response,
          errors: nil
        }
      end
    end

    private

    def client
      # We *especially* don't care about long running requests with this API, since it's dynamically enumerating all manifests
      # and parsing them when called (currently). We choose 120 secs because any larger is longer than the dg-api supports,
      # and it will end up throwing past then.
      @client ||= DependencyGraph::RepositoryDependenciesClient.new(request_timeout_seconds: 120)
    end

    def client_handler(&block)
      DependencyGraph::BaseTwirpClientHandler.client_handler({ class: "DependencyGraph::RepositoryDependenciesProvider" }, false, block)
    end
  end
end
