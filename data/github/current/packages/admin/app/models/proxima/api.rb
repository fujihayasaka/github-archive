# typed: true
# frozen_string_literal: true

module Proxima
  class Api
    SERVICE_NAME = "proxima"
    CONNECTION_OPEN_TIMEOUT = 1 # seconds

    # Initialize a Proxima::Api object.
    # Used as a base class.
    #
    # url - String of base API URL
    # hmac_key - String of client HMAC key for authentication
    # connection_timeout - defaults to 10s, but needs to be higher for certain endpoints
    #
    # Returns nothing.
    def initialize(url:, hmac_key:, connection_timeout: 10)
      @url = url
      @hmac_key = hmac_key
      @connection_timeout = connection_timeout
    end

    # Internal: Faraday connection.
    #
    # Returns a Faraday::Connection.
    def connection
      @connection ||= GitHub::FaradayClient.internal(SERVICE_NAME, url) do |conn|
        conn.headers = headers
        conn.options[:open_timeout] = CONNECTION_OPEN_TIMEOUT
        conn.options[:timeout] = @connection_timeout
        conn.use GitHub::FaradayMiddleware::Retries
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
      end
    end

    private

    attr_reader :url
    attr_reader :hmac_key
    attr_reader :connection_timeout

    # Private: Headers.
    #
    # Returns a Hash.
    def headers
      { "Content-Type" => "application/json" }
    end
  end
end
