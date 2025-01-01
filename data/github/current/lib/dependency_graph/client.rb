# typed: true
# frozen_string_literal: true

require "github/result"

module DependencyGraph
  class Client
    include GitHub::Tracing

    REQUEST_TIMEOUT = 5.0

    trace_method :post

    class ApiError < RuntimeError
      def initialize(message = nil, response: nil)
        super(message)
        @response = response
      end

      def message
        [super, @response&.status, @response&.body].compact.join("\n")
      end
    end

    TimeoutError = Class.new(ApiError)
    ServiceUnavailableError = Class.new(ApiError)
    FailedResponseError = Class.new(ApiError)
    InvalidResponseError = Class.new(ApiError)
    UnrecognizedManifestError = Class.new(ApiError)
    InvalidEncodedManifestError = Class.new(ApiError)
    GraphQLError = Class.new(ApiError)

    def self.default_circuit_breaker
      @circuit_breaker ||= Resilient::CircuitBreaker.get("dependency_graph", {
        instrumenter:               GitHub,
        sleep_window_seconds:       5,
        request_volume_threshold:   20,
        error_threshold_percentage: 50,
        window_size_in_seconds:     60,
        bucket_size_in_seconds:     10,
      })
    end

    def self.default_connection
      GitHub::FaradayClient::Internal.new(url: GitHub.dependency_graph_api_url) do |conn|
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.dependency_graph_api_hmac_key, header: "X-Request-HMAC"
        conn.use GitHub::FaradayMiddleware::RaiseError
        conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.dependency_graph_api_url
        conn.use DependencyGraph::UserTypeMiddleware
        conn.request :json
        conn.adapter :persistent_excon
      end
    end

    def initialize(connection: default_connection, circuit_breaker: default_circuit_breaker, timeout: REQUEST_TIMEOUT,
                   query_type: nil)
      @connection      = connection
      @circuit_breaker = circuit_breaker
      @timeout         = timeout
      @query_type      = query_type
    end

    def post(query, variables = {})
      raise ServiceUnavailableError if api_inaccessible?

      execute(query, variables).result
    rescue => error # rubocop:todo Lint/GenericRescue
      GitHub::Result.error(error)
    end

    private

    attr_reader :connection, :circuit_breaker

    def api_inaccessible?
      !circuit_breaker.allow_request?
    end

    def current_user
      GitHub.context[:actor]
    end

    def current_session_id
      GitHub.context[:actor_session].to_s
    end

    def request_url
      GitHub.context[:url]
    end

    def repository_is_public?
      GitHub.context[:is_public].to_s
    end

    def execute(data, variables)
      Response.new(connection.post do |request|
        request.options[:timeout] = @timeout
        request.headers["X-GitHub-User"] = current_user
        request.headers["X-GitHub-Session-Id"] = current_session_id
        request.headers["X-GitHub-Request-Url"] = request_url
        request.headers["X-GitHub-Is-Public"] = repository_is_public?
        request.headers["X-GitHub-DepGraph-Query-Type"] = @query_type if @query_type
        request.options[:open_timeout] = @timeout
        request.body = { query: data, variables: variables }.to_json
      end).tap do
        circuit_breaker.success
      end
    rescue Faraday::Error, Net::ReadTimeout => e
      record_timeout
      circuit_breaker.failure
      error = DependencyGraph::Client::TimeoutError.new(e.message)
      error.set_backtrace(e.backtrace)
      raise error
    end

    def default_connection
      self.class.default_connection
    end

    def default_circuit_breaker
      self.class.default_circuit_breaker
    end

    def record_timeout
      GitHub.dogstats.increment("dependency_graph_client.timeout")
    end

    class Response
      UNRECOGNIZED_MANIFEST_PATTERN = %r{manifest not recognized}i
      INVALID_ENCODED_MANIFEST_PATTERN = %r{Invalid encoded manifest}i

      attr_reader :response

      def initialize(response)
        @response = response
        @invalid = false
      end

      def result
        if success?
          GitHub::Result.new { parsed_body }
        elsif failure?
          raise FailedResponseError.new(response: self)
        elsif invalid?
          raise InvalidResponseError.new(response: self)
        elsif unrecognized_manifest?
          raise UnrecognizedManifestError.new(response: self)
        elsif invalid_encoded_manifest?
          raise InvalidEncodedManifestError.new(response: self)
        elsif errors?
          raise GraphQLError.new(response: self)
        else
          raise ApiError.new(response: self)
        end
      rescue ApiError => error
        GitHub::Result.error(error)
      end

      def success?
        !failure? && !invalid? && !errors?
      end

      def failure?
        !response.success?
      end

      def invalid?
        parsed_body # First, try to parse the body
        @invalid
      end

      def unrecognized_manifest?
        errors? && UNRECOGNIZED_MANIFEST_PATTERN.match?(errors)
      end

      def invalid_encoded_manifest?
        errors? && INVALID_ENCODED_MANIFEST_PATTERN.match?(errors)
      end

      def errors?
        errors.present?
      end

      def errors
        @errors ||=
          Array(parsed_body["errors"]).
            map { |e| e["message"] }.
            compact.
            join("\n")
      end

      def status
        response.status
      end

      def body
        response.body
      end

      private

      def parsed_body
        @parsed_body ||= GitHub::JSON.parse(body)
      rescue GitHub::JSON::ParseError
        @invalid = true
        @parsed_body = {}
      end
    end
  end
end
