# typed: true
# frozen_string_literal: true

require "proto-registry-metadata-api"

# Forcefully pull in twirp.rb to get error classes
::PackageRegistry::Twirp

module PackageRegistry
  module Twirp
    class BaseClient
      TWIRP_PATH = "twirp/"
      SERVICE_NAME = "package_registry_api"
      FAILBOT_APP_NAME = "github-package-registry-api-client"

      CONNECTION_OPEN_TIMEOUT = 30 # seconds
      READ_TIMEOUT = 30 # seconds

      def initialize(package_registry_hmac_key:, package_registry_url: GitHub.package_registry_url,
        connection_open_timeout: CONNECTION_OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        @package_registry_url = package_registry_url
        @package_registry_hmac_key = package_registry_hmac_key
        @connection_open_timeout = connection_open_timeout
        @read_timeout = read_timeout
      end

      # Wraps the TwirpClient#rpc method with common error response handling
      # behaviour for PackageRegistry
      def rpc(method, params)
        begin
          response = client.rpc(method, params)
        rescue Faraday::TimeoutError => error
          failbot_report(error)
          raise PackageRegistry::Twirp::Error, "PackageRegistry request timed out."
        rescue Faraday::ConnectionFailed => error
          failbot_report(error)
          raise PackageRegistry::Twirp::ServiceUnavailableError, "PackageRegistry could not connect."
        end

        return response.data if response.error.blank?

        case response.error.code
        when :not_found
          empty_message(method)
        when :failed_precondition
          handle_twirp_error(response.error, error_class: PackageRegistry::Twirp::FailedPreconditionError)
        when :already_exists
          handle_twirp_error(response.error, error_class: PackageRegistry::Twirp::AlreadyExistsError)
        when :permission_denied
          handle_twirp_error(response.error, error_class: PackageRegistry::Twirp::PermissionDeniedError, report: false)
        when :unavailable
          handle_twirp_error(response.error, error_class: PackageRegistry::Twirp::ServiceUnavailableError)
        when :invalid_argument
          handle_twirp_error(response.error, error_class: PackageRegistry::Twirp::InvalidArgumentError)
        else
          handle_twirp_error(response.error)
        end
      end

      private

      def twirp_class
        raise "#{self.class.name} must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
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

      def package_registry_configured?
        @package_registry_url.present? && @package_registry_hmac_key.present?
      end

      def build_client
        # If package_registry configuration has not been set for this GitHub install,
        # use a null connection as a circuit breaker so any client calls result
        # in a 503-like response.
        unless package_registry_configured?
          failbot_report(PackageRegistry::Twirp::Error.new("PackageRegistry configuration missing."))
          return PackageRegistry::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@package_registry_url, TWIRP_PATH)
      end

      def connection
        @connection ||= GitHub::FaradayClient::Internal.new(url: connection_url) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::TenantContext
          conn.use GitHub::FaradayMiddleware::CountryCode
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @package_registry_hmac_key
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.package_registry_url
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: GitHub,
            sleep_window_seconds: 2,
            request_volume_threshold: 20,
            error_threshold_percentage: 5,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
          conn.options[:open_timeout] = @connection_open_timeout
          conn.options[:timeout] = @read_timeout
          conn.adapter :persistent_excon
        end
      end

      def handle_twirp_error(twerr, error_class: PackageRegistry::Twirp::Error, report: true)
        error = error_class.new("[#{twerr.code}] #{twerr.msg}")
        error.msg = twerr.msg
        if report
          failbot_report(error)
        end
        raise error
      end

      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end
    end
  end
end
