# typed: true
# frozen_string_literal: true

module ActionsBroker
  module Twirp
    class BaseClient
      TWIRP_PATH = "/twirp"
      FAILBOT_APP_NAME = "github-actions-broker"
      SERVICE_NAME = "github-actions-broker"
      CONNECTION_OPEN_TIMEOUT = 1 # in seconds
      READ_TIMEOUT = 2 # in seconds

      def initialize(actions_broker_address: GitHub.actions_broker_address, actions_broker_twirp_hmac_keys: GitHub.actions_broker_twirp_hmac_keys)
        @actions_broker_address = actions_broker_address
        @actions_broker_twirp_hmac_keys = actions_broker_twirp_hmac_keys
      end

      # This method wraps the TwirpClient#rpc method with handling the errors
      # from a actions-broker response
      def rpc(method, params)
        begin
          response = client.rpc(method, params)
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
          failbot_report(error)

          raise ActionsBroker::Twirp::Error, "Actions Broker request timed out."
        end

        return response.data if response.error.blank?

        case response.error.code
        when :not_found
          empty_message(method)
        when :unavailable
          handle_twirp_error(response.error, error_class: ActionsBroker::Twirp::ServiceUnavailableError)
        else
          handle_twirp_error(response.error)
        end
      end

      private

      def hmac_key
        @hmac_key ||= @actions_broker_twirp_hmac_keys.split(" ").last
      end

      def actions_broker_configured?
        @actions_broker_address.present? && @actions_broker_twirp_hmac_keys.present?
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
        unless actions_broker_configured?
          failbot_report(ActionsBroker::Twirp::Error.new("Actions Broker HMAC and URL not set."))

          return ActionsBroker::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@actions_broker_address, TWIRP_PATH).to_s
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

      def handle_twirp_error(twirp_error, error_class: ActionsBroker::Twirp::Error)
        error = error_class.new("[#{twirp_error.code}] #{twirp_error.msg}")
        error.msg = twirp_error.msg
        failbot_report(error)

        raise error
      end

      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end
    end
  end
end
