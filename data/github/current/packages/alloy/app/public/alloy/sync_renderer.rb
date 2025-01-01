# typed: strict
# frozen_string_literal: true

module Alloy
  class SyncRenderer < BaseRenderer
    @@faraday_connection = T.let({}, T::Hash[T.nilable(String), Faraday::Connection])

    sig { returns(Alloy::Response) }
    def render
      # Don't try to SSR if there is no Alloy manifest present, unless Vite is handling the request locally
      return Response.new(status: 500, error: "Manifest is missing") if Alloy::Manifest.filename.blank? && !GitHub.vite_dev_server_enabled?

      # we short-circuit the request if the payload is too large so we don't have a JS error to report
      if payload_too_large?
        GitHub.logger.warn("Alloy render call failed", {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "http.status_code": 413,
          "http.url": @request[:path],
          "exception.message": "Payload Too Large"
        })
        return Response.new(status: 413)
      end

      response = with_request_timing do
        post_render
      end

      if !response.success?
        GitHub.logger.warn("Alloy render call failed", {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "http.status_code": response.status,
          "http.url": @request[:path],
          "exception.message": response.body
        })
      end

      Response::from_faraday_response(response)
    end

    sig { returns(Faraday::Response) }
    def post_render
      self.class.faraday_connection.post("/render", @request_payload, request_headers)
    end

    sig { returns(Faraday::Connection) }
    def self.faraday_connection
      alloy_url = self.request_url
      return T.must(@@faraday_connection[alloy_url]) if @@faraday_connection[alloy_url].present?
      @@faraday_connection[alloy_url] = Faraday.new(alloy_url) do |conn| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
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
      conn.use datadog_middleware, stats: GitHub.dogstats, service_name: "alloy", custom_tags: lambda { |env|
        ["app_name:#{env.request_headers[Alloy::Constants::REACT_APP_HEADER]}"]
      }

      conn.use GitHub::FaradayMiddleware::StaffRequest
      conn.use Alloy::FaradayMiddleware::CircuitBreaker

      conn.options[:open_timeout] = 0.250
      conn.options[:timeout] = GitHub.vite_dev_server_enabled? ? 5 : 2
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
    end
  end
end
