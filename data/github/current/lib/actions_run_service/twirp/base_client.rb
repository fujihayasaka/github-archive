# typed: true
# frozen_string_literal: true

module ActionsRunService
  module Twirp
    class BaseClient
      TWIRP_PATH = "twirp"
      FAILBOT_APP_NAME = "github-actions-run-service"
      SERVICE_NAME = "github-actions-run-service"
      CONNECTION_OPEN_TIMEOUT = 1 # in seconds
      READ_TIMEOUT = 2 # in seconds

      def initialize(base_url:, actions_run_service_twirp_hmac_keys: GitHub.actions_run_service_twirp_hmac_keys)
        @base_url = base_url
        @actions_run_service_twirp_hmac_keys = actions_run_service_twirp_hmac_keys
      end

      # This method wraps the TwirpClient#rpc method with handling the errors
      # from a actions-run-service response
      def rpc(method, params)
        TwirpHelper.rescue_from_twirp_errors(FAILBOT_APP_NAME, app: FAILBOT_APP_NAME) do
          client.rpc(method, params)
        end
      end

      private

      def hmac_key
        # The last key is the most recent key when keys are rotated
        @hmac_key ||= @actions_run_service_twirp_hmac_keys.split(" ").last
      end

      def actions_run_service_configured?
        @base_url.present? && @actions_run_service_twirp_hmac_keys.present?
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
        unless actions_run_service_configured?
          return ActionsRunService::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@base_url, TWIRP_PATH).to_s
      end

      def connection
        @connection ||= GitHub::FaradayClient::Internal.new(connection_url) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
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
    end
  end
end
