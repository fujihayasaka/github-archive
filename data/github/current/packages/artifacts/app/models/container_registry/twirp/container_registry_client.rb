# typed: true
# frozen_string_literal: true

# Forcefully pull in twirp.rb to get error classes
::ContainerRegistry::Twirp

module ContainerRegistry
  # The cake is a lie.. this uses REST but we act like it's twirp to re-use the error handling.
  module Twirp
    class ContainerRegistryClient
      extend T::Sig

      SERVICE_NAME = "container_registry_api"
      FAILBOT_APP_NAME = "github-container-registry-api-client"
      CONNECTION_OPEN_TIMEOUT = 30 # seconds
      READ_TIMEOUT = 30 # seconds

      def initialize(container_registry_url: GitHub.container_registry_url, container_registry_hmac_key: GitHub.container_registry_hmac_key,
        connection_open_timeout: CONNECTION_OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, connection: nil)
        @container_registry_url = container_registry_url
        @container_registry_hmac_key = container_registry_hmac_key
        @connection_open_timeout = connection_open_timeout
        @read_timeout = read_timeout
        @connection = connection
      end

      def get_blob(namespace:, digest:)
        begin
          request(:get, "/internal/#{namespace}/blobs/#{digest}") do |resp|
            return resp.body
          end
        rescue ContainerRegistry::Twirp::Error => error
        end
      end

      # Unlike `get_blob` this method raises if the request fails
      sig { params(actor_type: String, actor_id: Integer, blob_identifiers: T::Array[{ namespace: String, name: String, digest: String }]).returns(T::Array[String]) }
      def generate_presigned_urls(actor_type:, actor_id:, blob_identifiers:)
        request(:post, "/internal/presignedurls/generate", {
          actor_type: actor_type,
          actor_id: actor_id,
          blob_identifiers: blob_identifiers
      }.to_json) do |resp|
          h = JSON.parse(resp.body)
          return h["urls"]
        end
      end

      def request(method, path, params = {})
        begin
          resp = connection.send(method, path, params)
        rescue Faraday::TimeoutError => error
          failbot_report(error)
          raise ContainerRegistry::Twirp::Error, "ContainerRegistry request timed out."
        rescue Faraday::ConnectionFailed => error
          failbot_report(error)
          raise ContainerRegistry::Twirp::ServiceUnavailableError, "ContainerRegistry service unavailable."
        end

        yield resp if block_given? && resp.success?

        twerr = ContainerRegistry::Twirp::Error.new
        twerr.msg = resp.body
        handle_error(twerr)
      end

      private

      def connection
        @connection ||= GitHub::FaradayClient::Internal.new(url: @container_registry_url) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::TenantContext
          conn.use GitHub::FaradayMiddleware::CountryCode
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @container_registry_hmac_key
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

      def handle_error(twerr, error_class: ContainerRegistry::Twirp::Error)
        error = error_class.new
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
