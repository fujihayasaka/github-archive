# typed: true
# frozen_string_literal: true

module Spam
  class GeoAsnLookup
    CONNECTION_OPEN_TIMEOUT_IN_SECONDS = 2
    CONNECTION_TIMEOUT_IN_SECONDS = 4
    GEO_ASN_LOOKUP_URL = "https://geo-asn-lookup-production.service.iad.github.net"
    BULK_LOOKUP_PATH = "/geo"

    def self.connection
      @connection ||= begin
        headers = {
          "Content-Type" => "application/json",
        }

        Faraday.new(url: GEO_ASN_LOOKUP_URL, headers: headers) do |faraday|
          faraday.adapter(Faraday.default_adapter)
        end
      end
    end

    def self.is_tor_node?(address)
      return false if Rails.env.development?

      if result = lookup(address).first
        result["tor_exit_node"]
      else
        false
      end
    end

    def self.lookup(addresses)
      body = { ips: Array(addresses) }.to_json

      response = connection.post(BULK_LOOKUP_PATH, body) do |request|
        request.options.open_timeout = CONNECTION_OPEN_TIMEOUT_IN_SECONDS
        request.options.timeout = CONNECTION_TIMEOUT_IN_SECONDS
      end

      GitHub::JSON.parse(response.body)
    end
  end
end
