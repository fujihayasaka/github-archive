# typed: strict
# frozen_string_literal: true

module Alloy
  class AsyncRenderer < BaseRenderer
    @@faraday_connection = T.let({}, T::Hash[T.nilable(String), Faraday::Connection])

    sig { returns(ConcurrentFaraday::FutureResponse[Faraday::Response]) }
    def render
      # Don't try to SSR if there is no Alloy manifest present
      return build_promise_response(500, "Manifest is missing") if Alloy::Manifest.filename.blank? && !GitHub.vite_dev_server_enabled?

      # we short-circuit the request if the payload is too large so we don't have a JS error to report
      if payload_too_large?
        GitHub.logger.warn("Alloy render call failed", {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "http.status_code": 413,
          "http.url": @request[:path],
          "exception.message": "Payload Too Large"
        })
        return build_promise_response(413, "Payload too large")
      end

      promise = T.cast(self.class.faraday_connection.post("/render", @request_payload, request_headers), ConcurrentFaraday::FutureResponse[T.untyped])
      promise.then do |response|
        evt = promise.instrument_event
        report_request_timing(timing: evt.duration.round(2), response:)
      end
      promise
    end

    sig { returns(Faraday::Connection) }
    def self.faraday_connection
      alloy_url = self.request_url
      return T.must(@@faraday_connection[alloy_url]) if @@faraday_connection[alloy_url].present?
      @@faraday_connection[alloy_url] = ConcurrentFaraday.new(alloy_url) do |conn|
        self.setup_connection(conn)

        conn.adapter :concurrent_adapter, persistent: true
      end
    end

    sig { params(conn: T.untyped).void }
    def self.setup_connection(conn)
      datadog_middleware = ::GitHub::FaradayMiddleware::DatadogAsync
      conn.use ::GitHub::FaradayMiddleware::RequestID
      conn.use datadog_middleware, stats: GitHub.dogstats, service_name: "alloy", custom_tags: lambda { |env|
        ["app_name:#{env.request_headers[Alloy::Constants::REACT_APP_HEADER]}"]
      }
      conn.use GitHub::FaradayMiddleware::AsyncDuration
      conn.use GitHub::FaradayMiddleware::StaffRequest
      conn.use Alloy::FaradayMiddleware::CircuitBreaker

      conn.options[:open_timeout] = 2.0
      conn.options[:timeout] = 2
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
    end

    sig { params(status: Integer, error: String).returns(ConcurrentFaraday::FutureResponse[Faraday::Response]) }
    def build_promise_response(status, error)
      ConcurrentFaraday::FutureResponse.new.fulfill(Faraday::Response.new(status: status, body: error))
    end
  end
end
