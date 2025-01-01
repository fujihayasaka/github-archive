# typed: true
# frozen_string_literal: true

require "dependency-graph-platform-proto"

module DependencyGraphPlatform
  module Twirp
    class BaseClient
      TWIRP_PATH = "twirp/"
      SERVICE_NAME = "dependency_graph_platform"
      FAILBOT_APP_NAME = "dependency-graph-platform-twirp"
      DATADOG_PREFIX = "dependency_graph_platform.twirp"

      CONNECTION_OPEN_TIMEOUT = 1 # seconds
      DEFAULT_READ_TIMEOUT = 3 # seconds

      RESILENCY_OPTIONS = {
        instrumenter: GitHub,
        sleep_window_seconds: 10,
        request_volume_threshold: 20,
        error_threshold_percentage: 5,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 5,
      }

      attr_reader :connection

      sig { params(url: String, hmac: String, read_timeout_secs: Integer).returns(Faraday::Connection) }
      def self.build_connection(
        url: GitHub.dependency_graph_platform_url,
        hmac: GitHub.dependency_graph_platform_hmac_keys,
        read_timeout_secs: DEFAULT_READ_TIMEOUT
      )
        unless url.present? && hmac.present?
          error = InvalidConfigurationError.new("dependency-graph-platform configuration missing.")
          Failbot.report(error, { app: FAILBOT_APP_NAME })
          raise error
        end

        connection_url = URI.join(url, TWIRP_PATH).to_s
        hmac_key = hmac.split(" ").first

        GitHub::FaradayClient::Internal.new(connection_url) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: RESILENCY_OPTIONS
          conn.options[:open_timeout] = CONNECTION_OPEN_TIMEOUT
          conn.options[:timeout] = read_timeout_secs
          conn.adapter :persistent_excon
        end
      end

      sig do
        params(
          dependency_graph_platform_url: String,
          dependency_graph_platform_hmac_keys: String,
          connection: T.nilable(Faraday::Connection),
        ).void
      end
      def initialize(
        dependency_graph_platform_url: GitHub.dependency_graph_platform_url,
        dependency_graph_platform_hmac_keys: GitHub.dependency_graph_platform_hmac_keys,
        connection: nil
      )
        # If we've been given a connection, use it by preference, otherwise build one from configuration arguments.
        @connection = connection || self.class.build_connection(
          url: dependency_graph_platform_url,
          hmac: dependency_graph_platform_hmac_keys
        )
      end

      def rpc(method, params)
        begin
          start_time = Time.now
          response = client.rpc(method, params)
          track_response_time_for(method, start_time)
        rescue Faraday::TimeoutError => error
          GitHub.dogstats.increment("#{DATADOG_PREFIX}.timeout", tags: default_stats_tags(method:))
          GitHub.logger.error(
            "twirp client timed out",
            client: SERVICE_NAME,
            method: method,
            twirp_class: twirp_class_name,
            error: error
          )
          raise DependencyGraphPlatform::Twirp::Error, "Request timed out."
        end

        return response.data if response.error.blank?

        error_tags = default_stats_tags(method:).append("code:#{response.error.code}")
        case response.error.code
        when :not_found
          empty_message(method)
        when :unavailable
          handle_twirp_error(
            response.error,
            error_tags:,
            error_class: DependencyGraphPlatform::Twirp::ServiceUnavailableError
          )
        else
          handle_twirp_error(response.error, error_tags:)
        end
      end

      private

      def twirp_class
        raise NotImplementedError, "#{self.class} must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
      end

      def client_name
        raise NotImplementedError, "#{self.class} must define a client name."
      end

      def twirp_class_name
        twirp_class.name.demodulize
      end

      # This method is used in cases where the API returns a 404 to return
      # an appropriate blank protobuf response
      def empty_message(method)
        output_class = twirp_class.rpcs[method.to_s][:output_class]

        output_class.new
      end

      def client
        @client ||= twirp_class.new(connection)
      end

      def handle_twirp_error(twerr, error_tags:, error_class: DependencyGraphPlatform::Twirp::Error)
        error = error_class.new("[#{twerr.code}] #{twerr.msg}")
        error.msg = twerr.msg
        GitHub.dogstats.increment("#{DATADOG_PREFIX}.error", tags: error_tags)
        report_and_raise(error)
      end

      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end

      def report_and_raise(error)
        failbot_report(error)
        raise error
      end

      def track_response_time_for(method, start_time, tags: [])
        GitHub.dogstats.timing_since("#{DATADOG_PREFIX}.#{client_name}.#{method_tag(method)}.time", start_time, tags: tags)
      end

      def count_request_attempts(method, attempts, tags: [])
        GitHub.dogstats.count("#{DATADOG_PREFIX}.#{client_name}.#{method_tag(method)}.attempts", attempts, tags: tags)
      end

      def method_tag(method)
        method.to_s.underscore
      end

      def default_stats_tags(method:)
        [
          "method:#{method_tag(method)}",
          "class:#{client_name}"
        ]
      end
    end
  end
end
