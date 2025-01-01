# typed: true
# frozen_string_literal: true

module ActionsResults
  module Twirp
    class BaseClient

      TWIRP_PATH = "/twirp"
      FAILBOT_APP_NAME = "github-actions-results"
      SERVICE_NAME = "github-actions-results"
      CONNECTION_OPEN_TIMEOUT = 1 # in seconds
      READ_TIMEOUT = 10 # in seconds
      RETRY_OPTIONS = {
        client_name: SERVICE_NAME,
        retry_statuses: [500, 503],
        methods: [:post],
        exceptions: [
          Errno::ETIMEDOUT,
          "Timeout::Error",
          Faraday::TimeoutError,
          Faraday::ConnectionFailed,
          Faraday::RetriableResponse,
        ]
      }

      def initialize(
        actions_results_core_address: GitHub.actions_results_core_address,
        actions_results_core_twirp_hmac_keys: GitHub.actions_results_core_twirp_hmac_keys
      )
        @actions_results_core_address = actions_results_core_address
        @actions_results_core_twirp_hmac_keys = actions_results_core_twirp_hmac_keys
      end

      def rpc(method, params)
        TwirpHelper.rescue_from_twirp_errors(FAILBOT_APP_NAME, app: FAILBOT_APP_NAME) do
          client.rpc(method, params)
        end
      end

      private

      def hmac_key
        @hmac_key ||= @actions_results_core_twirp_hmac_keys.split(" ").last
      end

      def actions_results_configured?
        @actions_results_core_address.present? && @actions_results_core_twirp_hmac_keys.present?
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
        unless actions_results_configured?
          failbot_report(ActionsResults::Twirp::Error.new("Actions Results HMAC and URL not set."))

          return ActionsResults::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@actions_results_core_address, TWIRP_PATH).to_s
      end

      def connection
        @connection ||= GitHub::FaradayClient::Internal.new(connection_url) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, enable_path_tag: true
          conn.use GitHub::FaradayMiddleware::Retries, RETRY_OPTIONS
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: GitHub,
            sleep_window_seconds: 10,
            request_volume_threshold: 20,
            error_threshold_percentage: 5,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
          conn.use GitHub::FaradayMiddleware::TenantContext
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
