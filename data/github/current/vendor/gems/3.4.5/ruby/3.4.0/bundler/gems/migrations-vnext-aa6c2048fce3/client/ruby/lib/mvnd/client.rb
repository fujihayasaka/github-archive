# frozen_string_literal: true

require "faraday"
require "json"
require_relative "./v1/migrations_twirp"
require_relative "./hmac_middleware"
require_relative "./twirp_error"

module Mvnd
  class Client
    def initialize(host, faraday_options: {}, hmac_key: ENV["MVND_HMAC_KEY"])
      @host = host
      @hmac_key = hmac_key
      @faraday_options = {
        open_timeout: 1,
        timeout: 5,
        params_encoder: Faraday::FlatParamsEncoder
      }.merge(faraday_options)
    end

    def create_resource(resource)
      request = Mvnd::Migrations::Api::V1::CreateResourceRequest.new(resource: resource)
      response = twirp_client.create_resource(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    def store_event(event)
      request = Mvnd::Migrations::Api::V1::StoreEventRequest.new(event: event)
      response = twirp_client.store_event(request)
      return response.data if response.error.nil?

      raise TwirpError.new(twirp_response: response)
    end

    private

    def twirp_client
      @twirp_client ||= Mvnd::Migrations::Api::V1::MigrationClient.new(faraday)
    end

    def faraday
      Faraday.new([@host, "twirp"].join("/")) do |conn|
        conn.options.merge! @faraday_options
        conn.use Mvnd::Client::HMACMiddleware, @hmac_key
        conn.adapter(Faraday.default_adapter)
      end
    end
  end
end
