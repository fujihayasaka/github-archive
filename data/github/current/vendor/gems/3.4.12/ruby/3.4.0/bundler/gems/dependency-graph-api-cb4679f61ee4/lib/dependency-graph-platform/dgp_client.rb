require "dependency-graph-platform-proto"
require_relative "../dependency_graph/faraday_client/internal_twirp_with_retries"
require_relative "../faraday_middleware/datadog"
require_relative "../faraday_middleware/hmac_auth"
require_relative "../faraday_middleware/resilient"

module DependencyGraphAPI
  module DependencyGraphPlatform
    SERVICE_NAME = "dependency-graph-platform"

    module DGPClient
      def connection
        @connection ||= DependencyGraph::FaradayClient::InternalTwirpWithRetries.new(twirp_api_url) do |conn|
          configure_platform_client conn
        end
      end

      # We don't want to retry for write operations, so we use a separate connection without retries
      def write_connection
        @write_connection ||= DependencyGraph::FaradayClient::Internal.new(twirp_api_url) do |conn|
          configure_platform_client conn
        end
      end

      private

      def twirp_api_url
        @twirp_api_url ||= "#{Rails.application.config.dependency_graph_platform_url}/twirp"
      end

      def configure_platform_client(conn)
        if Rails.application.config.respond_to?(:dependency_graph_platform_hmac_keys)
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: Rails.application.config.dependency_graph_platform_hmac_keys[0]
        end
        conn.use GitHub::FaradayMiddleware::Datadog, stats: Rails.application.stats, service_name: SERVICE_NAME
        conn.use DependencyGraph::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
          instrumenter: ActiveSupport::Notifications
        }
      end
    end
  end
end
