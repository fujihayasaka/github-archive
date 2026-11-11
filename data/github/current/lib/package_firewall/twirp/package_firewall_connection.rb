# typed: true
# frozen_string_literal: true

require_relative "../twirp"

module PackageFirewall
  module Twirp
    # Faraday-backed connection wrapper for the PackageFirewall PolicyConfigAPI
    # Twirp service. Modeled on `OSSLicenseCompliance::Twirp::OSSLicenseComplianceConnection`.
    #
    # Subclasses (currently `PackageFirewallClient`) define `twirp_class` to
    # point at the generated Twirp client class and add typed wrappers for
    # individual RPCs.
    class PackageFirewallConnection
      include GitHub::Memoizer

      TWIRP_PATH = "twirp/"
      SERVICE_NAME = "PackageFirewall"
      FAILBOT_APP_NAME = "package-firewall-twirp"
      DATADOG_PREFIX = "package_firewall.twirp"

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
        url: GitHub.package_firewall_url,
        hmac: GitHub.package_firewall_hmac_key,
        read_timeout_secs: DEFAULT_READ_TIMEOUT
      )
        unless url.present? && hmac.present?
          error = PackageFirewall::Twirp::Error.new("package_firewall configuration missing.")
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
          package_firewall_url: String,
          package_firewall_hmac_key: String,
          connection: T.nilable(Faraday::Connection),
        ).void
      end
      def initialize(
        package_firewall_url: GitHub.package_firewall_url,
        package_firewall_hmac_key: GitHub.package_firewall_hmac_key,
        connection: nil
      )
        @connection = connection || self.class.build_connection(
          url: package_firewall_url,
          hmac: package_firewall_hmac_key,
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
            error: error,
          )
          raise PackageFirewall::Twirp::Error, "Request timed out."
        end

        return response.data if response.error.blank?

        error_tags = default_stats_tags(method:).append("code:#{response.error.code}")

        case response.error.code
        when :not_found
          handle_twirp_error(response.error, error_tags:, error_class: PackageFirewall::Twirp::NotFoundError)
        when :unavailable
          handle_twirp_error(response.error, error_tags:, error_class: PackageFirewall::Twirp::ServiceUnavailableError)
        when :invalid_argument
          handle_twirp_error(response.error, error_tags:, error_class: PackageFirewall::Twirp::InvalidArgumentError)
        else
          handle_twirp_error(response.error, error_tags:)
        end
      end

      private

      # Subclasses override this to point at the generated Twirp client class.
      def twirp_class
        raise NotImplementedError, "Subclass must define twirp_class"
      end

      def client_name
        "package_firewall_client"
      end

      def twirp_class_name
        twirp_class.name.demodulize
      end

      memoize def client
        twirp_class.new(connection)
      end

      def handle_twirp_error(twerr, error_tags:, error_class: PackageFirewall::Twirp::Error)
        error = error_class.new("[#{twerr.code}] #{twerr.msg}")
        error.msg = twerr.msg
        error.twirp_error = twerr
        GitHub.dogstats.increment("#{DATADOG_PREFIX}.error", tags: error_tags)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
        raise error
      end

      def track_response_time_for(method, start_time, tags: [])
        GitHub.dogstats.timing_since(
          "#{DATADOG_PREFIX}.#{client_name}.#{method_tag(method)}.time", start_time, tags: tags,
        )
      end

      def method_tag(method)
        method.to_s.underscore
      end

      def default_stats_tags(method:)
        [
          "method:#{method_tag(method)}",
          "class:#{client_name}",
        ]
      end
    end
  end
end
