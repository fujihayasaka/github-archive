# frozen_string_literal: true

require "faraday"
require "faraday/excon"
require "faraday/retry"
require_relative "../../faraday_middleware/request_id"

module DependencyGraph
  module FaradayClient
    class Internal < ::Faraday::Connection
      def initialize(url = nil, options = nil)
        super(url, options) do |conn|
          conn.use ::GitHub::FaradayMiddleware::RequestID
          conn.headers[:user_agent] = "dependency-graph-api"

          if Rails.application.fast_api_host?
            conn.options[:open_timeout] = 1
            conn.options[:timeout] = Rails.application.class::FAST_QUERY_TIMEOUT - 1  # Leave room for open_timeout
          end

          # Retry once on connection failures (stale persistent sockets).
          # This is safe even for writes: the request was never sent to the server,
          # so there is no idempotency concern — we are only reconnecting the TCP socket.
          conn.request :retry, {
            max: 1,
            methods: %i[get post put delete patch head options],
            retry_statuses: [],
            exceptions: [Faraday::ConnectionFailed],
          }

          conn.adapter :excon, persistent: true, persistent_timeout: 30

          yield(conn) if block_given?
        end
      end
    end
  end
end
