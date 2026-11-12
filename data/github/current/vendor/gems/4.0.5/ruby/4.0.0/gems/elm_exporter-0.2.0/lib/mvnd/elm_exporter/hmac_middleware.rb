# frozen_string_literal: true

require "openssl"
require "time"

module Mvnd
  module ElmExporter
    class HMACNotConfiguredError < StandardError
      def message
        "HMAC key is not configured. Pass a non-empty key when building the Faraday connection."
      end
    end

    # Signs requests to the elm-exporter MigrationManagerAPI Twirp server, which
    # validates the standard GitHub internal Request-HMAC header
    # (see github/elm-exporter internal/pkg/twirp/server.go).
    #
    # Header format: "<unix_ts>.<hex(HMAC-SHA256(key, unix_ts))>"
    class HMACMiddleware < Faraday::Middleware
      def initialize(app, hmac_key)
        @hmac_key = hmac_key
        super(app)
      end

      def hmac_header_value(timestamp: Time.now)
        timestamp = timestamp.to_i.to_s
        hmac_sign = OpenSSL::HMAC.hexdigest("sha256", @hmac_key, timestamp)
        "#{timestamp}.#{hmac_sign}"
      end

      def call(env)
        raise HMACNotConfiguredError if @hmac_key.nil? || @hmac_key.to_s.strip.empty?

        env.request_headers["Request-HMAC"] = hmac_header_value
        @app.call(env)
      end
    end
  end
end
