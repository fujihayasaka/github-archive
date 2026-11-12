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

          conn.adapter :excon

          yield(conn) if block_given?
        end
      end
    end
  end
end
