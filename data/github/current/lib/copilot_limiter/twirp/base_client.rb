# typed: true
# frozen_string_literal: true

module CopilotLimiter
  module Twirp
    class BaseClient

      TWIRP_PATH = "/twirp"
      FAILBOT_APP_NAME = "copilot-limiter"
      SERVICE_NAME = "copilot-limiter"
      CONNECTION_OPEN_TIMEOUT = 1 # in seconds
      READ_TIMEOUT = 1 # in seconds
      FARADAY_SLEEP_WINDOW_SECONDS = 10
      FARADAY_REQUEST_VOLUME_THRESHOLD = 5
      FARADAY_ERROR_THRESHOLD_PERCENTAGE = 50
      FARADAY_WINDOW_SIZE_IN_SECONDS = 30
      FARADAY_BUCKET_SIZE_IN_SECONDS = 5
      RETRY_OPTIONS = {
        client_name: SERVICE_NAME,
        retry_statuses: [500, 503],
        methods: [:post],
        retry_block: proc { GitHub.dogstats.increment("twirp.#{SERVICE_NAME}.retries") },
        exceptions: [
          Errno::ETIMEDOUT,
          "Timeout::Error",
          Faraday::TimeoutError,
          Faraday::ConnectionFailed,
          Faraday::RetriableResponse,
        ]
      }

      def initialize(copilot_limiter_url: GitHub.copilot_limiter_url, copilot_limiter_hmac_key: GitHub.copilot_limiter_hmac_key)
        @copilot_limiter_url = copilot_limiter_url
        @copilot_limiter_hmac_key = copilot_limiter_hmac_key
      end

      def rpc(method, params)
        name = "#{self.class.name.to_s.demodulize.parameterize(separator: "_")}_#{method.to_s.underscore}"
        GitHub.tracer.in_span(name, kind: :internal) do |_span|
          TwirpHelper.rescue_from_twirp_errors(FAILBOT_APP_NAME, app: FAILBOT_APP_NAME) do
            GitHub.dogstats.distribution_time("#{name}.latency") do
              response = client.rpc(method, params)
              # response is a Twirp::ClientResp actually (https://github.com/arthurnn/twirp-ruby/blob/main/lib/twirp/client_resp.rb)
              GitHub.dogstats.increment("#{name}.called")
              response
            end
          end
        end
      end

      private

      def hmac_key
        @hmac_key ||= @copilot_limiter_hmac_key.split(" ").last
      end

      def copilot_limiter_configured?
        @copilot_limiter_url.present? && @copilot_limiter_hmac_key.present?
      end

      # This method is used in the case where the API returns a 404 and properly formed
      # blank protocol buffer ;)
      def empty_message(method)
        output_class = twirp_class.rpcs[method.to_s][:output_class]

        output_class.new
      end

      def twirp_class
        raise "Must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
      end

      def client
        @client ||= build_client
      end

      def build_client
        unless copilot_limiter_configured?
          failbot_report(CopilotLimiter::Twirp::Error.new("Copilot Limiter HMAC and URL not set."))

          return CopilotLimiter::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@copilot_limiter_url, TWIRP_PATH).to_s
      end

      def connection
        @connection ||= GitHub::FaradayClient::Internal.new(connection_url) do |conn|
          conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"

          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::Retries, RETRY_OPTIONS
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: GitHub,
            sleep_window_seconds: FARADAY_SLEEP_WINDOW_SECONDS,
            request_volume_threshold: FARADAY_REQUEST_VOLUME_THRESHOLD,
            error_threshold_percentage: FARADAY_ERROR_THRESHOLD_PERCENTAGE,
            window_size_in_seconds: FARADAY_WINDOW_SIZE_IN_SECONDS,
            bucket_size_in_seconds: FARADAY_BUCKET_SIZE_IN_SECONDS,
          }
          conn.options[:open_timeout] = CONNECTION_OPEN_TIMEOUT
          conn.options[:timeout] = READ_TIMEOUT
          conn.adapter :persistent_excon
        end
      end

      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end
    end
  end
end
