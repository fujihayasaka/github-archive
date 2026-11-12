# typed: true
# frozen_string_literal: true

require "faraday"
require "notifyd/plug"

module Notifyd
  # The RetryPlug configures the built in retry middleware in Faraday v0.17
  # It will also send stats on every retry if the stats instance is set
  class RetryPlug
    include Plug

    attr_reader :stats

    def initialize(stats: nil)
      @stats = stats
    end

    def inject(conn)
      retry_block = proc do |env, _options, retries, exception|
        next unless stats

        tags = [
          "status:#{env[:status]}",
          "retries:#{retries}",
          "twirp_endpoint:#{env[:url].request_uri.sub("/twirp/", "")}",
          "error:#{exception.class}",
        ]
        stats.increment("notifyd.client.retry", tags:)
      end

      conn.request :retry, {
        retry_statuses: [*500...600],
        exceptions: [
          Errno::ETIMEDOUT,
          "Timeout::Error",
          Faraday::TimeoutError,
          Faraday::RetriableResponse,
          Faraday::ConnectionFailed,
        ],
        interval: 0.05,
        retry_if: lambda { |_env, _exception| true }, # Always retry.
        retry_block:,
        interval_randomness: 0.5,
        backoff_factor: 2,
        max: 2,
      }
    end
  end
end
