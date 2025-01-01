# typed: true
# frozen_string_literal: true

module Alloy
  PreloadedQueryVariables = T.type_alias { T::Hash[String, T.untyped] }
  PreloadedQueryResult = T.type_alias { T::Hash[String, T.untyped] }
  PreloadedQuery = T.type_alias { { queryId: String, variables: PreloadedQueryVariables, result: PreloadedQueryResult } }

  class Response
    attr_reader :status, :result
    attr_accessor :error, :preloaded_queries

    sig { params(status: Integer, result: T.nilable(String), error: T.nilable(String), preloaded_queries: T.nilable(T::Array[PreloadedQuery])).void }
    def initialize(status:, result: "", error: nil, preloaded_queries: nil)
      @status = status
      @result = result
      @error = error
      @preloaded_queries = preloaded_queries
    end

    def success?
      result.present?
    end

    sig { params(response: Faraday::Response).returns(T.attached_class) }
    def self.from_faraday_response(response)
      if response.body.nil? || !response.success?
        new(status: response.status, error: response.body.dup.force_encoding("UTF-8"))
      elsif response.headers["content-type"].include?("application/json")
        # Alloy is an internal service and we have full control over it,
        # so we can assume that it will always return a safe response.
        json_response = JSON.parse(response.body)
        new(
          status: response.status,
          result: json_response["html"].force_encoding("UTF-8"),
          preloaded_queries: json_response["preloadedQueries"],
        )
      else
        new(status: response.status, result: response.body.dup.force_encoding("UTF-8"))
      end
    end
  end

  class BaseRenderer
    ASSETS_PATH = "public/assets"
    HMAC_TOKEN_DIGEST = OpenSSL::Digest::SHA256
    MAX_SIZE = 1.megabyte
    MANIFEST_PATH = Rails.root.join(ASSETS_PATH, "manifest.alloy.json")

    class << self
      # Returns the HTML rendered by Alloy.
      #
      # @param request [Hash] the request payload to pass to the Alloy handler
      # @returns [Alloy::Response, ConcurrentFaraday::FutureResponse] the response from Alloy
      sig { params(request: Hash, metadata: Hash).returns(T.any(Response, ConcurrentFaraday::FutureResponse[T.untyped])) }
      def render(request:, metadata: {})
        raise NotImplementedError, "Implement in a subclass"
      end

      private

      sig { returns(Faraday::Connection) }
      def faraday_connection
        raise NotImplementedError, "Implement in a subclass"
      end

      sig { params(request: Hash, metadata: Hash).returns(String) }
      def request_payload(request, metadata)
        payload = {
          arg: request,
          metadata: metadata,
          manifestUrl: full_manifest_url
        }

        payload[:cdnPath] = "http://github.localhost/webpack/" if GitHub.webpack_dev_server_enabled?

        payload.to_json
      end

      sig { returns(Hash) }
      def request_headers
        {
          "REQUEST_HMAC" => hmac_token,
          "Content-Type" => "application/json",
        }
      end

      sig { params(conn: T.untyped).void }
      def setup_connection(conn)
        raise NotImplementedError, "Implement in a subclass"
      end

      sig { params(stat: String, app_name: String, tier: Integer, metadata: Hash).returns(Faraday::Response) }
      def with_request_timing(stat, app_name, tier, metadata)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        response = yield

        timing = (1000 * (Process.clock_gettime(Process::CLOCK_MONOTONIC) - now)).round
        tags = ["app_name:#{app_name}", "status_code:#{response.status}", "status:#{response.success? ? "success" : "failure"}"]

        tags << "controller:#{metadata[:controller]}" if metadata[:controller]
        tags << "action:#{metadata[:action]}" if metadata[:action]
        tags << "referrer_controller:#{metadata[:referrer_controller]}" if metadata[:referrer_controller]
        tags << "referrer_action:#{metadata[:referrer_action]}" if metadata[:referrer_action]
        tags << "logged_in:#{metadata[:logged_in].present?}"
        tags << "staff:#{metadata[:staff]}"
        tags << "catalog_service:#{metadata[:catalog_service]}"
        tags << "tier:#{tier}"

        GitHub.dogstats.distribution(stat, timing, tags: tags)

        response
      end

      # In development, we can update the alloy bundle without restarting the server,
      # so we have to make sure that we're always using the latest version.
      # This is not an issue for prod since the bundle won't change
      sig { returns(String) }
      def manifest_filename
        manifest["manifest"]
      end

      sig { returns(String) }
      def hmac_token
        timestamp = Time.now.to_i.to_s
        digest = HMAC_TOKEN_DIGEST.new
        hmac = OpenSSL::HMAC.new(GitHub.alloy_api_hmac_key, digest)
        hmac << timestamp
        hmac << full_manifest_url
        "#{timestamp}.#{hmac}"
      end

      sig { returns(String) }
      def full_manifest_url
        "#{handler_host}/#{manifest_filename}"
      end

      sig { returns(String) }
      def handler_host
        return "http://github.localhost/assets" if Rails.env.development?

        File.join(GitHub.alloy_asset_host_url, "assets")
      end

      sig { params(payload: String).returns(T::Boolean) }
      def payload_too_large?(payload)
        payload.bytesize > MAX_SIZE
      end

      # In development, we can update the alloy bundle without restarting the server,
      # so we have to make sure that we're always using the latest version.
      # This is not an issue for prod since the bundle won't change
      def manifest
        return parse_manifest(MANIFEST_PATH) if Rails.env.development?
        return @@parsed_manifest if defined?(@@parsed_manifest)

        @@parsed_manifest = parse_manifest(MANIFEST_PATH)
        @@parsed_manifest
      end

      def parse_manifest(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end
    end
  end

  class AsyncRenderer < BaseRenderer
    sig { params(request: Hash, metadata: Hash).returns(T.any(Response, ConcurrentFaraday::FutureResponse[T.untyped])) }
    def self.render(request:, metadata: {})
      # Don't try to SSR if there is no Alloy manifest present
      return Response.new(status: 500) if manifest_filename.blank?

      payload = request_payload(request, metadata)

      # we short-circuit the request if the payload is too large so we don't have a JS error to report
      if payload_too_large?(payload)
        GitHub.logger.warn("Alloy render call failed", {
          "code.namespace": self.name,
          "code.function": __method__,
          "http.status_code": 413,
          "http.url": request[:path],
          "exception.message": "Payload Too Large"
        })
        return Response.new(status: 413)
      end

      self.faraday_connection.post("/render", payload, request_headers)
    end

    sig { returns(Faraday::Connection) }
    def self.faraday_connection
      @@faraday_connection ||= ConcurrentFaraday.new(GitHub.alloy_url) do |conn|
        self.setup_connection(conn)

        conn.adapter :concurrent_adapter, persistent: true
      end
    end

    sig { params(conn: T.untyped).void }
    def self.setup_connection(conn)
      datadog_middleware = ::GitHub::FaradayMiddleware::DatadogAsync
      conn.use ::GitHub::FaradayMiddleware::RequestID
      conn.use datadog_middleware, stats: GitHub.dogstats, service_name: "alloy"
      conn.use GitHub::FaradayMiddleware::AsyncDuration
      conn.use ::GitHub::FaradayMiddleware::Resilient, name: "alloy", options: {
        instrumenter: GitHub,
        # Seconds after tripping circuit before allowing retry
        sleep_window_seconds: 10,
        # % of "marks" that must be failed to trip the circuit
        error_threshold_percentage: 5,
        # Number of seconds in the statistical window
        window_size_in_seconds: 30,
        # Size of buckets in statistical window
        bucket_size_in_seconds: 5,
      }

      conn.options[:open_timeout] = 2.0
      conn.options[:timeout] = 2
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
    end
  end

  class SyncRenderer < BaseRenderer
    sig { params(request: Hash, metadata: Hash).returns(T.any(Response, ConcurrentFaraday::FutureResponse[T.untyped])) }
    def self.render(request:, metadata: {})
      # Don't try to SSR if there is no Alloy manifest present
      return Response.new(status: 500) if manifest_filename.blank?

      payload = request_payload(request, metadata)

      # we short-circuit the request if the payload is too large so we don't have a JS error to report
      if payload_too_large?(payload)
        GitHub.logger.warn("Alloy render call failed", {
          "code.namespace": self.name,
          "code.function": __method__,
          "http.status_code": 413,
          "http.url": request[:path],
          "exception.message": "Payload Too Large"
        })
        return Response.new(status: 413)
      end

      response = with_request_timing("alloy.gh.render.time", request[:name], request[:tier], metadata) do
        post_render(request: request, payload: payload, metadata: metadata)
      end

      if !response.success?
        GitHub.logger.warn("Alloy render call failed", {
          "code.namespace": self.name,
          "code.function": __method__,
          "http.status_code": response.status,
          "http.url": request[:path],
          "exception.message": response.body
        })
      end

      Response::from_faraday_response(response)
    end

    sig { params(request: Hash, payload: String, metadata: Hash).returns(Faraday::Response) }
    def self.post_render(request:, payload:, metadata:)
      faraday_connection.post("/render", payload, request_headers)
    end

    sig { returns(Faraday::Connection) }
    def self.faraday_connection
      @@faraday_connection ||= Faraday.new(GitHub.alloy_url) do |conn|
        setup_connection(conn)

        conn.adapter :persistent_excon, {
          tcp_nodelay: true,
          keepalive: {
            time: 60,
            intvl: 5,
            probes: 3,
          }
        }
      end
    end

    sig { params(conn: T.untyped).void }
    def self.setup_connection(conn)
      datadog_middleware = ::GitHub::FaradayMiddleware::Datadog
      conn.use ::GitHub::FaradayMiddleware::RequestID
      conn.use datadog_middleware, stats: GitHub.dogstats, service_name: "alloy"
      conn.use ::GitHub::FaradayMiddleware::Resilient, name: "alloy", options: {
        instrumenter: GitHub,
        # Seconds after tripping circuit before allowing retry
        sleep_window_seconds: 10,
        # % of "marks" that must be failed to trip the circuit
        error_threshold_percentage: 5,
        # Number of seconds in the statistical window
        window_size_in_seconds: 30,
        # Size of buckets in statistical window
        bucket_size_in_seconds: 5,
      }

      conn.options[:open_timeout] = 0.250
      conn.options[:timeout] = 2
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
    end
  end
end
