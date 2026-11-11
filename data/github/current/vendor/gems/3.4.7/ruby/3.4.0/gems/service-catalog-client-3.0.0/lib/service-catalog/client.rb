# typed: false
# frozen_string_literal: true

require "active_support/core_ext/string/inflections"
require "active_support/notifications"
require "json"
require "net/http"
require "stringio"
require "uri"

module ServiceCatalog
  # Client is the class for executing GraphQL requests against a Service Catalog API.
  class Client
    # Error is a generic error class when something goes wrong.
    class Error < StandardError; end

    # Seconds for the process to sleep between retries after encountering an error.
    DEFAULT_SLEEP_BETWEEN_RETRIES = 1

    # List of Ruby error classes to retry by default.
    # @return [Array] default list of exceptions to rescue
    DEFAULT_ERROR_CLASSES_TO_RETRY = [
      EOFError,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      SocketError,
      Net::OpenTimeout,              # Couldn't open a connection.
      Net::ReadTimeout,              # Timed out reading a response.
      Net::HTTPFatalError,           # The Error class for HTTP errors
      Net::HTTPRequestTimeOut,       # 408
      Net::HTTPInternalServerError,  # 500
      Net::HTTPBadGateway,           # 502
      Net::HTTPServiceUnavailable,   # 503
      Net::HTTPGatewayTimeOut,       # 504
    ].freeze

    # List of errors we frequently see due to dns/network flakiness.
    # Consider rescuing these when making client calls.
    # @return [Array] list of connection related exceptions to rescue
    ConnectionErrors = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      SocketError,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED
    ].freeze

    # The full HTTPS URL to the Service Catalog GraphQL API.
    # @return [String] the full endpoint
    attr_reader :endpoint

    # The Authorization token for accessing the endpoint.
    # @return [String] the authorization token
    attr_reader :token

    # A URI class representation of the endpoint attribute.
    # @return [URI] the endpoint as a URI
    attr_reader :uri

    # A global sleep duration setting for all requests this client will execute.
    # @return [Float] the sleep duration in seconds
    attr_reader :sleep_duration

    # Additional options passed during creation of the Client.
    # @return [Hash] the options
    attr_reader :options

    # Create a new Client.
    #
    # @param endpoint [String] Full HTTP URL to the GraphQL API endpoint
    # @param token [String] Authorization token
    # @param tracer [Tracer] OpenTelemetry Tracer, must respond to `in_span` (optional)
    # @param options [Hash] Further options with symbol keys (+sleep_duration+ can be set this way)
    def initialize(endpoint:, token:, tracer: nil, options: {})
      @endpoint = endpoint
      @token = token
      @tracer = tracer
      @uri = URI.parse(endpoint)
      @options = options
      @sleep_duration = options[:sleep_duration] || DEFAULT_SLEEP_BETWEEN_RETRIES
    end

    # Build HTTP headers for API call.
    #
    # @param context [Hash] (optional) list of additional headers to add
    #
    # @return [Hash] HTTP headers
    def headers(context = {})
      default_headers = {
        "User-Agent"    => "service-catalog-client/#{ServiceCatalog::Client::VERSION}",
        "Authorization" => "Bearer #{token}",
      }
      default_headers.merge!(context[:headers] || {}) if context
      default_headers
    end

    # Return the HTTP connection to the endpoint
    #
    # @return [Net::HTTP] HTTP client
    def connection
      Net::HTTP.new(uri.host, uri.port).tap do |client|
        client.use_ssl = uri.scheme == "https"
        client.open_timeout = options[:open_timeout] || 5
        client.read_timeout = options[:read_timeout] || 5
        if client.respond_to?(:write_timeout=)
          client.write_timeout = options[:write_timeout] || 5
        end
      end
    end

    # Execute GraphQL query against server.
    #
    # @param query [String] GraphQL query
    # @param variables [Hash] (optional) Variables for GraphQL query
    # @param context [Hash] (optional) Additional headers
    #
    # @return [Hash] GraphQL response, along with HTTP response as +"raw_response"+ key
    def query(query:, variables: {}, context: {})
      request = Net::HTTP::Post.new(uri.request_uri)

      request.basic_auth(uri.user, uri.password) if uri.user || uri.password

      request["Accept"] = "application/json"
      request["Accept-Encoding"] = "gzip"
      request["Content-Type"] = "application/json"
      headers(context).each { |name, value| request[name] = value }

      body = {}
      body["query"] = query.to_s
      body["variables"] = variables if variables.any?
      request.body = JSON.generate(body)

      response = nil
      ActiveSupport::Notifications.instrument("service_catalog_client.query", body) do
        record_trace_span("service_catalog_client.query", attributes: body) do
          response = connection.request(request)
        end
      end
      response_data = case response
      when Net::HTTPOK, Net::HTTPBadRequest
        parse_response_body(response)
      else
        { "errors" => [{ "message" => "#{response.code} #{response.message}" }] }
      end

      response_data["raw_response"] = response

      response_data
    end

    # Run a query and retry on non-success responses.
    #
    # @param query [String] GraphQL query
    # @param variables [Hash] (optional) Variables for GraphQL query
    # @param context [Hash] (optional) Additional headers
    # @param max_retries [Integer] (optional) Maximum number of times to retry this query if it fails
    # @param retriable_error_classes [Array<Exception>] (optional) Acceptable error classes to retry from.
    #
    # @return (see #query)
    def query_with_retries(query:, variables: {}, context: {}, max_retries: 3, retriable_error_classes: DEFAULT_ERROR_CLASSES_TO_RETRY)
      retries_left ||= max_retries
      response_data = query(query: query, variables: variables, context: context)
      case response_data["raw_response"]
      when Net::HTTPOK, Net::HTTPBadRequest
        return response_data
      else
        raise response_data["raw_response"].error_type.new(
          "#{response_data["raw_response"].class} #{parse_response_body(response_data["raw_response"])}",
          response_data["raw_response"]
        )
      end
    rescue *retriable_error_classes
      raise unless retries_left > 0
      retries_left -= 1
      sleep sleep_duration
      retry
    end

    # Access the Groups-related API calls.
    #
    # @return [GroupsQueryBuilder]
    def groups
      @groups ||= GroupsQueryBinder.new(client: self)
    end

    # Access the Owners-related API calls.
    #
    # @return [OwnersQueryBuilder]
    def owners
      @owners ||= OwnersQueryBinder.new(client: self)
    end

    # Access the Scorecards-related API calls.
    #
    # @return [ScorecardsQueryBinder]
    def scorecards
      @scorecards ||= ScorecardsQueryBinder.new(client: self)
    end

    # Access the ScorecardJobs-related API calls.
    #
    # @return [ScorecardJobsQueryBinder]
    def scorecard_jobs
      @scorecard_jobs ||= ScorecardJobsQueryBinder.new(client: self)
    end

    # Access the Services-related API calls.
    #
    # @return [ServicesQueryBinder]
    def services
      @services ||= ServicesQueryBinder.new(client: self)
    end

    # Access the SLO-related API calls.
    #
    # @return [SlosQueryBinder]
    def slos
      @slos ||= SlosQueryBinder.new(client: self)
    end

    # Access the Subscriptions-related API calls.
    #
    # @return [SubscriptionsQueryBinder]
    def subscriptions
      @subscriptions ||= SubscriptionsQueryBinder.new(client: self)
    end

    # Access the Task Lock-related API calls.
    #
    # @return [TaskLocksQueryBinder]
    def task_locks
      @task_locks ||= TaskLocksQueryBinder.new(client: self)
    end

    # Access the User-related API calls.
    #
    # @return [UsersQueryBinder]
    def users
      @users ||= UsersQueryBinder.new(client: self)
    end

    private

    # Parse response body into JSON.
    # Handles GZIP compression.
    def parse_response_body(response)
      body_text = if "gzip" == response["Content-Encoding"]
                    gz = ::Zlib::GzipReader.new(StringIO.new(response.body))
                    gz.read
      else
        response.body
      end

      if response["Content-Type"].to_s.start_with?("application/json")
        JSON.parse(body_text)
      else
        {"text" => body_text}
      end
    end

    # Record span to the tracer. If tracer isn't set, trace is skipped.
    #
    # @param name [String] Span name
    # @param attributes [Hash] Custom attributes to send with the span
    #
    # @yield Code to record
    def record_trace_span(name, attributes: {})
      if @tracer.nil?
        yield
      else
        @tracer.in_span(name, attributes: flatten_attributes_for_otel(attributes).merge!({"span.kind" => "internal"})) do
          yield
        end
      end
    end

    def flatten_attributes_for_otel(attributes)
      attributes.each_with_object({}) do |(key, value), memo|
        # Rework Arrays into Hashes.
        if value.is_a?(Array)
          value = value.each.with_object({}).with_index do |(value2, memo), index|
            memo[index.to_s] = value2
          end
        end

        # Recursively flatten Hashes, or assign the key-value pair if the value is simple.
        if value.is_a?(Hash)
          flatten_attributes_for_otel(value).each do |key2, value2|
            memo[key.to_s+"."+key2.to_s] = value2
          end
        else
          memo[key.to_s] = value
        end
      end
    end
  end
end

Dir[File.expand_path("client/*.rb", __dir__)].each { |f| require f }
