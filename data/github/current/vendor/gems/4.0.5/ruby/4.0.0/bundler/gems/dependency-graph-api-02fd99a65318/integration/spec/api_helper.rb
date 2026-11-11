require "debug"
require "faraday"
require "json"
require "openssl"

module ApiHelper

  class DependencyGraphClient
    def initialize(url: "http://localhost:9596/")
      @url = url
    end

    def graphql(query, hmac: hmac_token)
      response = connection.post("/query") do |request|
        request.headers["X-Request-Hmac"] = hmac
        request.body = { query: query }
      end

      return response.status, response.status == 200 ? JSON.parse(response.body) : {}
    end

    private

    def connection
      @connection ||= Faraday.new(url: @url) do |conn|
        conn.request :json
        conn.adapter Faraday.default_adapter
      end
    end

    def hmac_token
      integration_env = ENV.fetch("DEPENDENCY_GRAPH_API_HMAC_KEYS", "").split(" ").first
      timestamp = Time.now.to_i.to_s
      digest = OpenSSL::Digest::SHA256.new
      hmac = OpenSSL::HMAC.new(integration_env, digest)
      hmac << timestamp
      "#{timestamp}.#{hmac}"
    end
  end
end
