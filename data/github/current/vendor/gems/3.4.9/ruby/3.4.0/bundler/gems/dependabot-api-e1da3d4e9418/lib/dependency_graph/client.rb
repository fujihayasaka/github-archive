# frozen_string_literal: true

require "dependency-snapshots-api-proto"
require "twirp"

require "./lib/middleware/hmac_authentication_twirp"

module DependencyGraph
  class Client < ::Twirp::Client
    client_for Github::DependencySnapshotsApi::DependabotServiceService

    TWIRP_ENDPOINT = "/twirp"

    def initialize(url: nil)
      @url = url
      connection = build_connection
      super(connection)
    end

    private

    def build_connection
      url = @url || dependency_snapshot_api_url

      retry_options = {
        max: 2,
        interval: 0.05,
        interval_randomness: 0.5,
        backoff_factor: 2,
        methods: [], # Twirp will use POST so don't filter by default methods
        exceptions: [Faraday::ConnectionFailed],
      }
      Faraday.new(url: url) do |conn|
        conn.use Middleware::HMACAuthenticationTwirp, hmac_key: hmac_key
        conn.adapter Faraday::Adapter::NetHttp
        conn.request :retry, retry_options
      end
    end

    def dependency_snapshot_api_url
      URI.join(dependency_snapshot_api_internal_url, TWIRP_ENDPOINT)
    end

    def dependency_snapshot_api_internal_url
      Prius.get(:dsapi_internal_url)
    end

    def hmac_key
      Prius.get(:dsapi_hmac_key)
    end
  end
end
