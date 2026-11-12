# frozen_string_literal: true

require "monolith-twirp-actions-core"

require "./lib/middleware/hmac_authentication_twirp"

module GitHub
  module Twirp
    class Error < StandardError; end

    class Client
      TWIRP_ENDPOINT = "internal/twirp"

      def initialize(github_api_url:, hmac_key:)
        @github_api_url = github_api_url
        @hmac_key = hmac_key
      end

      def connection
        @connection ||= build_connection
      end

      private

      def url
        @url ||= URI.join(@github_api_url, TWIRP_ENDPOINT)
      end

      def build_connection
        retry_options = {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2,
          methods: [], # Twirp will use POST so don't filter by default methods
          exceptions: [Faraday::ConnectionFailed],
        }
        Faraday.new(url: url) do |conn|
          conn.use Middleware::HMACAuthenticationTwirp, hmac_key: @hmac_key
          conn.adapter Faraday::Adapter::NetHttp
          conn.request :retry, retry_options
        end
      end
    end
  end
end
