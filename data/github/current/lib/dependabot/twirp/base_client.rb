# typed: true
# frozen_string_literal: true

require "proto-dependabot-api"

module Dependabot
  module Twirp
    class BaseClient
      TWIRP_PATH = "twirp/"
      SERVICE_NAME = "dependabot_api"
      FAILBOT_APP_NAME = "github-dependabot-api-client"

      CONNECTION_OPEN_TIMEOUT = 1 # seconds
      READ_TIMEOUT = 3 # seconds

      def initialize(dependabot_url: GitHub.dependabot_url, dependabot_hmac_key: GitHub.dependabot_hmac_key)
        @dependabot_url = dependabot_url
        @dependabot_hmac_key = dependabot_hmac_key
      end

      # Wraps the TwirpClient#rpc method with common error response handling
      # behaviour for Dependabot
      def rpc(method, params)
        begin
          response = client.rpc(method, params)
        rescue Faraday::TimeoutError => error
          failbot_report(error)
          raise Dependabot::Twirp::Error, "Dependabot request timed out."
        end

        return response.data if response.error.blank?

        case response.error.code
        when :not_found
          empty_message(method)
        when :unavailable
          handle_twirp_error(response.error, error_class: Dependabot::Twirp::ServiceUnavailableError)
        else
          handle_twirp_error(response.error)
        end
      end

      private

      def twirp_class
        raise "#{self.class} must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
      end

      # This method is used in cases where the API returns a 404 to return
      # an appropriate blank protobuf response
      def empty_message(method)
        output_class = twirp_class.rpcs[method.to_s][:output_class]

        output_class.new
      end

      def client
        @client ||= build_client
      end

      def dependabot_configured?
        @dependabot_url.present? && @dependabot_hmac_key.present?
      end

      def build_client
        # If dependabot configuration has not been set for this GitHub install,
        # use a null connection as a circuit breaker so any client calls result
        # in a 503-like response.
        unless dependabot_configured?
          failbot_report(Dependabot::Twirp::Error.new("Dependabot configuration missing."))
          return Dependabot::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@dependabot_url, TWIRP_PATH)
      end

      def connection
        @connection ||= Faraday.new(url: connection_url) do |conn|
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @dependabot_hmac_key
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

      def handle_twirp_error(twerr, error_class: Dependabot::Twirp::Error)
        error = error_class.new("[#{twerr.code}] #{twerr.msg}")
        error.msg = twerr.msg
        failbot_report(error)
        raise error
      end

      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end
    end
  end
end
