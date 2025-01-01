# typed: true
# frozen_string_literal: true

require "issues-graph"

module GitHub
  module Config
    module IssuesGraphApiConfig
      extend self

      # Public: returns a memoized instance of the IssuesGraph::Client
      # configured with various settings for logging, timeouts, etc.
      #
      # Returns an instance of IssuesGraph::Client
      sig { returns(IssuesGraph::Client) }
      def issues_graph_api_client
        @issues_graph_api_client ||= begin
          conn = ::Faraday.new(GitHub.issues_graph_api_url) do |conn|
            configure_issues_graph_api_connection_options(conn)
            conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: "issues-graph"
            conn.adapter Faraday.default_adapter
          end

          ::IssuesGraph::Client.new(conn, GitHub.issues_graph_hmac_key, {
            dogstats: GitHub.dogstats,
            logger: GitHub::Logger,
          })
        end
      end

      # Public: returns a memoized instance of the IssuesGraph::Client
      # configured with various settings for logging, timeouts, etc.
      #
      # Notably this has a lower timeout than the issues_graph_api_client.
      #
      # Returns an instance of IssuesGraph::Client
      def issues_graph_api_client_strict
        @issues_graph_api_client_strict ||= begin
          conn = ::Faraday.new(GitHub.issues_graph_api_url) do |conn|
            configure_issues_graph_api_connection_options(conn)
            conn.options[:timeout] = 2 # Importantly, lower the default timeout
            conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: "issues-graph"
            conn.adapter Faraday.default_adapter
          end

          ::IssuesGraph::Client.new(conn, GitHub.issues_graph_hmac_key, {
            dogstats: GitHub.dogstats,
            logger: GitHub::Logger,
          })
        end
      end

      def async_issues_graph_api_client
        @async_issues_graph_api_client ||= begin
          conn = ::ConcurrentFaraday.new(GitHub.issues_graph_api_url) do |conn|
            configure_issues_graph_api_connection_options(conn)
            conn.use GitHub::FaradayMiddleware::DatadogAsync, stats: GitHub.dogstats, service_name: "issues-graph"
            conn.adapter :concurrent_adapter, persistent: true
          end

          ::IssuesGraph::Client.new(conn, GitHub.issues_graph_hmac_key, {
            dogstats: GitHub.dogstats,
            logger: GitHub::Logger,
          })
        end
      end

      # Public: returns a memoized instance of the IssuesGraph::Client
      # configured with various settings for logging, timeouts, etc.
      #
      # It is recommended to NOT use this without a feature flag. This client
      # increases the potential for slow responses in exchange for getting
      # some data to be returned by having higher timeouts.
      def issues_graph_api_client_slow
        @issues_graph_api_client_slow ||= begin
          conn = ::Faraday.new(GitHub.issues_graph_api_url) do |conn|
            configure_issues_graph_api_connection_options(conn)
            conn.options[:timeout] = 4 # Importantly, set a higher timeout
            conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: "issues-graph"
            conn.adapter Faraday.default_adapter
          end

          ::IssuesGraph::Client.new(conn, GitHub.issues_graph_hmac_key, {
            dogstats: GitHub.dogstats,
            logger: GitHub::Logger,
          })
        end
      end

      def issues_graph_api_is_enabled(actor = nil)
        GitHub.flipper[:issues_graph_api].enabled?(actor)
      end

      def issues_graph_api_disable_denormalized_read_is_enabled(actor = nil)
        GitHub.flipper[:issues_graph_api_disable_denormalized_read].enabled?(actor)
      end

      private def configure_issues_graph_api_connection_options(conn)
        conn.options[:open_timeout] = 2 # seconds
        conn.options[:timeout] = 4 # seconds

        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::Resilient, name: "issues-graph", options: {
          instrumenter: GitHub,

          # Seconds after tripping circuit before allowing retry
          sleep_window_seconds: 5,

          # % of "marks" that must be failed to trip the circuit
          error_threshold_percentage: 25,

          # Number of seconds in the statistical window
          window_size_in_seconds: 60,

          # Size of buckets in statistical window
          bucket_size_in_seconds: 10,
        }
      end

      alias_method :issues_graph_api_enabled?, :issues_graph_api_is_enabled
      alias_method :issues_graph_api_disable_denormalized_read_enabled?, :issues_graph_api_disable_denormalized_read_is_enabled
    end
  end

  extend Config::IssuesGraphApiConfig
end
