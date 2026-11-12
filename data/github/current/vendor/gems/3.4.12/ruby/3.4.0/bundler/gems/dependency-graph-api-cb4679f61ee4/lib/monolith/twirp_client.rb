require "twirp"
require "faraday"
require_relative "../dependency_graph/faraday_client/internal_twirp_with_retries"
require_relative "../faraday_middleware/datadog"
require_relative "../faraday_middleware/hmac_auth"

module Monolith
  class TwirpClient

    class Error < RuntimeError; end
    class ConfigNotFoundError < Error; end

    def initialize(service:)
      @service = service

      config = Rails.application.config_for(:monolith).with_indifferent_access

      @api_url = config.fetch("base_uri", "")
      raise ConfigNotFoundError.new "base_uri must not be blank (service: #{service}, environment: #{Rails.env})" if @api_url.blank?

      @hmac_key = config.fetch("client_key")
      @connection_open_timeout = config.fetch("connection_open_timeout")
      @connection_read_timeout = config.fetch("connection_read_timeout")
    end

    private

    def client
      raise NotImplementedError
    end

    def connection
      @connection ||= build_connection
    end

    def build_connection
      DependencyGraph::FaradayClient::InternalTwirpWithRetries.new(url: "#{@api_url}/twirp") do |conn|
        conn.use GitHub::FaradayMiddleware::Datadog, stats: Rails.application.stats, service_name: @service
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @hmac_key
        conn.options[:open_timeout] = @connection_open_timeout
        conn.options[:timeout] = @connection_read_timeout
      end
    end
  end
end
