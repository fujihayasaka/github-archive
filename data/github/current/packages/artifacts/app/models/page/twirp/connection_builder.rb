# typed: true
# frozen_string_literal: true

class Page
  module Twirp
    class ConnectionBuilder
      attr_reader :url, :hmac_key, :service_name

      # Public: Construct a Twirp connection factory.
      #
      # url - The internal Twirp API URL, as a String.
      # hmac_key - The client HMAC key, as a String.
      def initialize(url: GitHub.pages_deployer_url, hmac_key: GitHub.pages_deployer_hmac_key, service_name:)
        @url = url
        @hmac_key = hmac_key
        @service_name = service_name
      end

      # Public: Build a Faraday::Connection instance.
      def build
        Faraday.new(url: url) do |conn|
          conn.headers[:user_agent] = "github-#{service_name}/#{GitHub.current_sha}"
          conn.options[:open_timeout] = 0.5
          conn.request :retry,
            max: 3, # max number of retries
            interval: 0.05, # pause in seconds between retries
            interval_randomness: 0.5, # max possible additional time in seconds added to each retry interval
            backoff_factor: 1.2, # the amount to multiply each successive retry interval
            methods: [:post], # all Twirp requests are POSTs
            exceptions: [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
            retry_block: proc { GitHub.dogstats.increment("rpc.#{service_name}.retries") }

          conn.use ::GitHub::FaradayMiddleware::RequestID
          conn.use ::GitHub::FaradayMiddleware::Datadog, service_name: service_name, stats: GitHub.dogstats
          conn.use ::GitHub::FaradayMiddleware::HMACAuth, hmac_key: @hmac_key
          conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
          conn.adapter :typhoeus
        end
      end
    end
  end
end
