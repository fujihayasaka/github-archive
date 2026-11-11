# frozen_string_literal: true

require "openssl"
require "time"

module Mvnd
  class Client
    class HMACNotConfiguredError < StandardError
      def message
        "HMAC is not configured correctly, please set the MVND_HMAC_KEY environment variable"
      end
    end

    class HMACMiddleware < Faraday::Middleware
      def initialize(app, hmac_key)
        @hmac_key = hmac_key
        super(app)
      end
      # returns the proper hmac header value for the given timestamp and key
      # something like: "1546398245.2f4cf31546abda26f137f90eec8b297972aa7c145cdf22ac2b48dd980a0f19c1"
      def hmac_header_value(timestamp: Time.now)
        timestamp = timestamp.to_i.to_s
        hmac_sign = OpenSSL::HMAC.hexdigest("sha256", @hmac_key, timestamp)
        "#{timestamp}.#{hmac_sign}"
      end

      def call(env)
        if @hmac_key.nil? || @hmac_key.to_s.strip.empty?
          raise HMACNotConfiguredError.new
        end
        env.request_headers["Request-HMAC"] = hmac_header_value
        @app.call(env)
      end
    end
  end
end
