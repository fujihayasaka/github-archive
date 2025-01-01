# typed: true
# frozen_string_literal: true

module DependencySnapshot
  class BaseClient
    SERVICE_NAME = "github-dependency-snapshots-api".freeze
    FAILBOT_APP_NAME = "github-dependency-snapshots".freeze

    # Create a new client for a given Twirp class.
    #
    # - request_timeout_seconds: number of sections before a request times out
    # - connection: the Faraday connection to use for the client. If not provided, a new one will be created.
    # - use_json: useful for test code to override the default connection and use JSON encoding
    def initialize(request_timeout_seconds: 10, connection: nil, use_json: false)
      @request_timeout_seconds = request_timeout_seconds
      @connection = connection
      @client_content_type = use_json ? Twirp::Encoding::JSON : nil
    end

    sig { params(method: String, params: Hash).returns(Object) }
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

    attr_reader :client_content_type

    def is_tripped?(response)
      # we use different criteria than GitHub::FaradayMiddleware::Resilient#is_tripped?
      # because Twirp returns an error object rather than a Faraday-like response object
      response.error.meta[:http_error_from_intermediary] == "true" && response.error.meta[:status_code] == "502"
    end

    def twirp_class
      raise "#{self.class} must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
    end

    def client
      @client ||= twirp_class.new(connection, content_type: client_content_type)
    end

    def configure_middleware(connection)
      connection.use ::GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.dependency_snapshots_api_hmac_key, header: "X-Request-HMAC"
      connection.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      connection.use ::GitHub::FaradayMiddleware::Staffbar, url: GitHub.dependency_snapshots_api_url
      connection.use ::GitHub::FaradayMiddleware::RaiseError

      connection.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
        instrumenter: GitHub,
        sleep_window_seconds: 10,
        error_threshold_percentage: 5,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 5,
      }

      connection.options[:open_timeout] = 5 # seconds
      connection.options[:timeout] = @request_timeout_seconds

      connection.adapter :persistent_excon
    end

    def connection
      @connection ||= GitHub::FaradayClient::Internal.new(url: GitHub.dependency_snapshots_api_url) do |conn|
        configure_middleware(conn)
      end
    end
  end
end
