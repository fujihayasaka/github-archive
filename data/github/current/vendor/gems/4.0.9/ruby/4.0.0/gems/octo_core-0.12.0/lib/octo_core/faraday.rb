# typed: strict
# frozen_string_literal: true

require "faraday"
require "octo_core/faraday/hmac"
require "github/telemetry"
require "github/telemetry/faraday_middleware"

module OctoCore
  module Faraday
    extend T::Sig

    sig { params(url: String, hmac_key: String).returns(::Faraday::Connection) }
    def self.new_connection(url, hmac_key)
      ::Faraday.new(url) do |conn|
        conn.headers[:user_agent] = OctoCore::AppEnvironment.qualified_app_name

        conn.options[:open_timeout] = 0.250
        conn.options[:timeout] = 0.250

        conn.use GitHub::Telemetry::FaradayMiddleware::RequestId, hostname: OctoCore::AppEnvironment.host_name
        conn.use HMAC, hmac_key
      end
    end
  end
end
