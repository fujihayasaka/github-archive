# typed: true
# frozen_string_literal: true

require "faraday"

module GitHub
  module FaradayClient
    class External < ::Faraday::Connection
      # Delegate to ::Faraday::Connection but set proxy to flow through Network Proxy
      def initialize(url = nil, options = nil)
        super(url, options) do |conn|
          conn.proxy = GitHub.external_communication_proxy_host if conn.proxy.nil?

          yield(conn) if block_given?
        end
      end
    end
  end
end
