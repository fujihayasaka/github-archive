# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsdatastream-core"

module ActionsDataStream
  module Twirp
    class BaseClient

      TWIRP_PATH = "/twirp"
      FAILBOT_APP_NAME = "github-actions-data-stream"
      SERVICE_NAME = "github-actions-data-stream"
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
        address: GitHub.actions_data_stream_twirp_address,
        hmac_keys: GitHub.actions_data_stream_twirp_hmac_key
      )
        @address = address
        @hmac_keys = hmac_keys
      end

      def rpc(method, params)
        TwirpHelper.rescue_from_twirp_errors(FAILBOT_APP_NAME, app: FAILBOT_APP_NAME) do
          client.rpc(method, params)
        end
      end

      private

      def hmac_key
        @hmac_key ||= @hmac_keys.split(" ").last
      end

      def configured?
        @address.present? && @hmac_keys.present?
      end

      def empty_message(method)
        output_class = twirp_class.rpcs[method.to_s][:output_class]
        output_class.new
      end

      def twirp_class
        raise "#{self.class.name} must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
      end

      def client
        @client ||= build_client
      end

      def build_client
        unless configured?
          failbot_report(ActionsDataStream::Twirp::Error.new("Actions Data Stream HMAC and URL not set."))
          return ActionsDataStream::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@address, TWIRP_PATH).to_s
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
