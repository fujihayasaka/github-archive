# typed: strict
# frozen_string_literal: true

require "github/faraday_adapter/persistent_excon"

module Stars
  class Starry
    SERVICE_NAME = "starry"
    DEFAULT_STARRY_URL = "http://localhost:8080/twirp"

    sig { returns(::Starry::Proto::UserClient) }
    def self.client
      @client ||= T.let(::Starry::Proto::UserClient.new(
        GitHub::FaradayClient::Internal.new(service_url) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::TenantContext
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::Retries, {
            max: 2,
            interval: 0.05,
            interval_randomness: 0.5,
            backoff_factor: 2,
            exceptions: [
              Errno::ETIMEDOUT,
              "Timeout::Error",
              Faraday::TimeoutError,
              Faraday::ConnectionFailed,
              Faraday::RetriableResponse,
            ],
            retry_statuses: [502, 503]
          }
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            request_volume_threshold: 2,
            error_threshold_percentage: 60,
          }
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: ENV["STARRY_SHARED_HMAC_KEY"]
          conn.options[:open_timeout] = 0.1
          conn.options[:timeout] = 0.2
          conn.adapter :persistent_excon
        end
      ), T.nilable(::Starry::Proto::UserClient))
    end

    sig { returns(T::Boolean) }
    def self.enabled?
      hmac_key.present?
    end

    sig { returns(String) }
    def self.service_url
      ENV.fetch("STARRY_URL", DEFAULT_STARRY_URL)
    end

    sig { returns(String) }
    def self.hmac_key
      ENV.fetch("STARRY_SHARED_HMAC_KEY", "")
    end
  end
end
