# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client"

module DependencyReview
  class HealthClient < DependencyGraph::BaseTwirpClient
    # Play ping pong with dependency-graph-api
    def ping
      rpc(:Ping, {})
    end

    private

    def twirp_class
      DependencyGraphAPI::V1::HealthAPIClient
    end

    def twirp_url_namespace
      "health"
    end
  end
end
