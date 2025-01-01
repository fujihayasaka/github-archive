# frozen_string_literal: true

require "faraday"
require_relative "./internal"

module DependencyGraph
  module FaradayClient
    # Extend the config from the Internal client
    class InternalTwirpWithRetries < ::DependencyGraph::FaradayClient::Internal
      def initialize(url = nil, options = nil)
        super(url, options) do |conn|

          # Override default retry options for Twirp clients
          conn.request :retry, {
            # All Twirp operations are POST requests
            methods: %i[post],
            max: 3,
            retry_statuses: [
              # Too Many Requests
              429,
              # Internal Server Error
              500,
              # Bad Gateway
              502,
              # Service Unavailable
              503
            ],
            exceptions: [
              Errno::ETIMEDOUT, Timeout::Error, Faraday::TimeoutError,
              # We hit a lot of these, because the remote service kills the connection unexpectedly.
              Faraday::ConnectionFailed
            ]
          }

          yield(conn) if block_given?
        end
      end
    end
  end
end
