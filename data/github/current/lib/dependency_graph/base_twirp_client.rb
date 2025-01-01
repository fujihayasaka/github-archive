# typed: true
# frozen_string_literal: true

require "proto-dependency-graph-api"

module DependencyGraph
  class BaseTwirpClient
    SERVICE_NAME = "github-dependency-graph-twirp-api".freeze
    FAILBOT_APP_NAME = "github-dependency-graph".freeze
    TWIRP_PATH = "twirp".freeze

    # Error classes to handle any errors the Twirp API returns.
    class Error < StandardError; end
    class NotFoundError < Error; end
    class CircuitBrokenError < Error; end
    class BadRequestError < Error; end
    class ApiNotConfiguredError < Error; end
    class MalformedError < Error; end

    def initialize(request_timeout_seconds: 10, retryable: true, retry_options: {}, connection: nil, use_json: false)
      @request_timeout_seconds = request_timeout_seconds
      @retryable = retryable
      @retry_options = retry_options
      @connection = connection
      @use_json = use_json
    end

    def rpc(method, params)
      response = client.rpc(method, params)

      return response.data if response.error.blank?

      case response.error.code
      when :not_found
        raise NotFoundError, response.error.try(:msg) || response.error
      when :bad_route
        raise NotFoundError, response.error.try(:msg) || response.error
      when :unavailable
        raise CircuitBrokenError, response.error if is_tripped?(response)
        raise Error, response.error
      when :invalid_argument
        raise BadRequestError, "Invalid required argument(s): #{response.error.meta["argument"]}"
      when :malformed
        raise MalformedError, response.error.try(:msg) || response.error
      else
        raise Error, response.error
      end
    end

    private

    attr_reader :use_json

    def is_tripped?(response)
      # we use different criteria than GitHub::FaradayMiddleware::Resilient .is_tripped? because Twirp is not a fully "real" response
      response.error.meta[:http_error_from_intermediary] == "true" && response.error.meta[:status_code] == "502"
    end

    def twirp_class
      raise "#{self.class} must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
    end

    # Because dependency-graph-api mounts our Twirp Services at different paths in routes.rb, we need our client
    # classes to specify the path where the service is available. This should be a hard-coded string.
    #
    # Returns string or raises an error if the subclass doesn't override.
    def twirp_url_namespace
      raise "#{self.class} must define 'twirp_url_namespace' to return a Twirp::Client class that describes the remote service."
    end

    def client
      content_type = use_json ? Twirp::Encoding::JSON : nil
      @client ||= twirp_class.new(connection, content_type: content_type)
    end

    def connection_url
      if GitHub.dependency_graph_api_slow_query_url.blank?
        raise ApiNotConfiguredError.new("The Dependency Graph API is not configured. Please set the " +
                                    "DEPENDENCY_GRAPH_API_URL environment variable and restart the server.")
      end
      URI.join(GitHub.dependency_graph_api_slow_query_url, File.join(TWIRP_PATH, twirp_url_namespace))
    end

    def connection
      @connection ||= GitHub::FaradayClient::Internal.new(url: connection_url) do |conn|
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.dependency_graph_api_hmac_key, header: "X-Request-HMAC"
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
        conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.dependency_graph_api_url
        conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
          instrumenter: GitHub,
          sleep_window_seconds: 10,
          error_threshold_percentage: 5,
          window_size_in_seconds: 30,
          bucket_size_in_seconds: 5,
        }
        conn.use DependencyGraph::UserTypeMiddleware
        if @retryable
          # Individual classes should set retryable=false if they want to disable retries, eg. for a write operation.
          retry_options = {
            max: 3,
            retry_statuses: [429, 502, 503, 504],
            # All twirp requests are POSTs
            methods: [:post]
          }.merge(@retry_options)
          conn.request :retry, retry_options
        end
        conn.options[:open_timeout] = 5 # seconds
        conn.options[:timeout] = @request_timeout_seconds
        conn.adapter :persistent_excon
      end
    end
  end
end
