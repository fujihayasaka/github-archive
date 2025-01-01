# typed: strict
# frozen_string_literal: true

module Alloy
  class Warmup
    # rubocop:disable Style/ClassVars
    @@faraday_connection = T.let(nil, T.nilable(Faraday::Connection))

    HMAC_TOKEN_DIGEST = OpenSSL::Digest::SHA256

    sig { params(manifest: String).void }
    def initialize(manifest)
      @manifest = T.let(manifest, T.nilable(String))
      @manifest_url = T.let("#{Alloy::Manifest.handler_host}/#{manifest}", String)
    end

    sig { returns(String) }
    attr_reader :manifest_url

    sig { returns(T.nilable(String)) }
    attr_reader :manifest

    sig { returns(Faraday::Response) }
    def call
      self.class.faraday_connection.post("/warmup", { manifestUrl: @manifest_url }.to_json, request_headers)
    end

    sig { returns(T::Hash[String, String]) }
    def request_headers
      {
        "REQUEST_HMAC" => hmac_token,
        "Content-Type" => "application/json",
      }
    end

    sig { returns(String) }
    def hmac_token
      timestamp = Time.now.to_i.to_s
      digest = HMAC_TOKEN_DIGEST.new
      hmac = OpenSSL::HMAC.new(GitHub.alloy_api_hmac_key, digest)
      hmac << timestamp
      hmac << @manifest_url
      "#{timestamp}.#{hmac}"
    end

    sig { returns(Faraday::Connection) }
    def self.faraday_connection
      return @@faraday_connection unless @@faraday_connection.nil?
      @@faraday_connection = Faraday.new(GitHub.alloy_url) do |conn| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
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
      conn.use Alloy::FaradayMiddleware::CircuitBreaker

      conn.options[:open_timeout] = 0.250
      conn.options[:timeout] = GitHub.vite_dev_server_enabled? ? 5 : 2
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
    end
  end
end
