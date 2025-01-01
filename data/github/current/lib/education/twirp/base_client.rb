# typed: true
# frozen_string_literal: true

require "proto-education-web"

module Education
  module Twirp
    class BaseClient
      TWIRP_PATH = "twirp/"
      SERVICE_NAME = "education_web"
      FAILBOT_APP_NAME = "github-education-web-client"
      FEATURE_FLAG_NOT_ENABLED = "Education Web twirp is not currently enabled for this user."

      CONNECTION_OPEN_TIMEOUT = 1 # seconds
      READ_TIMEOUT = 3 # seconds

      def initialize(
        education_twirp_url: GitHub.education_twirp_url,
        education_hmac_key: GitHub.education_hmac_key,
        use_json: false,
        user:
      )
        @education_twirp_url = education_twirp_url
        @education_hmac_key = education_hmac_key
        @use_json = use_json
        @user = user
      end

      # Wraps the TwirpClient#rpc method with common error response handling
      # behaviour for Education
      def rpc(method, params)
        if !Flipper.enabled?("education-dev-pack-application", @user)
          unavailable = ::Twirp::Error.unavailable(FEATURE_FLAG_NOT_ENABLED)
          return ::Twirp::ClientResp.new(data: nil, error: unavailable)
        end
        response = client.rpc(method, params)

        return ::Twirp::ClientResp.new(data: response.data, error: nil) if response.error.blank?

        error_type = if response.error.code == :not_found
          Education::Twirp::NotFoundError
        elsif response.error.code == :unavailable
          Education::Twirp::ServiceUnavailableError
        else
          Education::Twirp::Error
        end

        handle_twirp_error(
          response.error.code,
          response.error.msg,
          error_type,
        )

      rescue Faraday::TimeoutError
        handle_twirp_error(
          :timeout,
          "Education request timed out.",
          Education::Twirp::TimeoutError
        )
      end

      private

      attr_reader :use_json

      def twirp_class
        raise(
          "#{self.class} must define 'twirp_class' to return a Twirp::Client class "\
            "that describes the remote service."
        )
      end

      def client
        @client ||= build_client
      end

      def education_configured?
        @education_twirp_url.present? && @education_hmac_key.present?
      end

      def build_client
        # If Education configuration has not been set for this GitHub install,
        # use a null connection as a circuit breaker so any client calls result
        # in a 503-like response.
        unless education_configured?
          failbot_report(Education::Twirp::Error.new("Education configuration missing."))
          return Education::Twirp::NullClient.new
        end

        content_type = use_json ? ::Twirp::Encoding::JSON : ::Twirp::Encoding::PROTO
        twirp_class.new(connection, content_type:)
      end

      def connection_url
        URI.join(@education_twirp_url, TWIRP_PATH)
      end

      def connection
        @connection ||= Faraday.new(url: connection_url) do |conn|
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @education_hmac_key
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: GitHub,
            sleep_window_seconds: 10,
            request_volume_threshold: 20,
            error_threshold_percentage: 5,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
          conn.options[:open_timeout] = CONNECTION_OPEN_TIMEOUT
          conn.options[:timeout] = READ_TIMEOUT
          conn.adapter :persistent_excon
        end
      end

      def handle_twirp_error(code, msg, error_class)
        error = error_class.new("[#{code}] #{msg}")
        error.msg = msg
        failbot_report(error)
        ::Twirp::ClientResp.new(data: nil, error: error)
      end

      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end
    end
  end
end
