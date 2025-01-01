# typed: true
# frozen_string_literal: true

require "faraday"
require_relative "../faraday_middleware/tenant_context"

module GitHub
  module FaradayClient
    class Internal < ::Faraday::Connection
      def initialize(url = nil, options = nil)
        super(url, options) do |conn|
          conn.use ::GitHub::FaradayMiddleware::RequestID
          conn.use ::GitHub::FaradayMiddleware::TenantContext
          yield(conn) if block_given?
        end
      end
    end
  end
end
