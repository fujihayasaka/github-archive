# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class ApiHmacClient
      SERVICE_NAME = "internal-apps-api"

      class Error < StandardError; end
      class NetworkError < Error; end
      class RequestError < Error; end
      class NotFoundError < Error; end

      attr_reader :hmac_key
      private :hmac_key

      def initialize(hmac_key = nil)
        @hmac_key = hmac_key || GitHub::Config::AppsInternalAPI.hmac_secrets.first
      end

      def syncable_apps(sync_records: [], party_type: "first")
        payload = build_payload(sync_records: sync_records, party_type: party_type)

        raw_response = hmac_client.post("/internal/apps/proxima_app_synchronizations", payload)

        handle_raw_response(raw_response)
      end

      def app_manifest(id:)
        raw_response = hmac_client.get("/internal/apps/proxima_app_manifest/#{id}")

        handle_raw_response(raw_response)
      end

      private

      def build_payload(sync_records:, party_type:)
        {
          "apps" => sync_records.map do |record|
            attributes = {}
            attributes["global_relay_id"] = record.dotcom_global_id
            attributes["fingerprint"] = record.fingerprint
            attributes
          end,
          "party" => party_type
        }.to_json
      end

      def handle_raw_response(raw_response)
        handle_request_error(raw_response)

        JSON.parse(raw_response.body)
      end

      def handle_request_error(res)
        return if res.success?

        case res.status
        when 404
          raise NotFoundError.new(res.body)
        when 400..499
          raise RequestError.new(res.body)
        else
          raise NetworkError.new("something went wrong")
        end
      end

      def hmac_client
        @connection ||= ::GitHub::FaradayClient::Internal.new(
          GitHub::Config::AppsInternalAPI.api_url
        ) do |conn|
          conn.options[:open_timeout] = 10
          conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"

          conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
          conn.use ::GitHub::FaradayMiddleware::HMACAuth, hmac_key: @hmac_key
          conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2

          conn.adapter :typhoeus
        end
      end
    end
  end
end
