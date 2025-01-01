# typed: true
# frozen_string_literal: true

module GitHub
  module Connect
    class S4

      ERROR_METRICS_RESPONSE = {
        blob: "Unable to download metrics.",
        record_count: 0, content_type: "text/plain"
      }.freeze

      def initialize
        @client = client if s4_enabled?
      end

      def s4_enabled?
        return @s4_enabled if defined?(@s4_enabled)
        if s4_host
          @s4_enabled = true
        else
          @s4_enabled = false
        end
      end
      attr_accessor :s4_enabled

      def s4_host
        GitHub.environment.fetch("S4_HOST", @s4_host)
      end
      attr_writer :s4_host

      def client
        return @client if defined?(@client)
        @client ||= ::S4::V1::Client.new(
          s4_host,
          hmac_key: s4_hmac_key
        )
      end
      attr_writer :client

      def s4_hmac_key
        GitHub.environment["S4_HMAC_KEY"]
      end

      def find_owner(enterprise_or_org)
        login = enterprise_or_org.to_s
        @current_org ||= Organization.find_by_login(login) if login.present?
        @current_enterprise ||= Business.find_by(slug: enterprise_or_org)

        @current_enterprise || @current_org || nil
      end

      def record_count(owner_id)
        return 0 unless s4_enabled?

        client.count(owner_id)
      rescue ::S4::V1::Client::ResponseError => e
        Failbot.report(e)
        0 # If we can't connect to S4, act like we have 0 S4 stats
      end

      def metrics_export(owner_id, format: "json", filtered: true)
        if filtered
          response = client.filtered_metrics(owner_id, format: format)
        else
          response = client.metrics(owner_id, format: format)
        end

        case format
        when "csv"
          content_type = "text/csv"
          record_count = CSV.parse(response).count - 1
        when "json"
          content_type = "application/json"
          record_count = JSON.parse(response).count
        end
        # Send back our data and metadata
        { blob: response, record_count: record_count, content_type: content_type }
      rescue ::S4::V1::Client::ResponseError => e
        Failbot.report(e)
        ERROR_METRICS_RESPONSE
      end
    end
  end
end
