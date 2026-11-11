# typed: true
# frozen_string_literal: true

module Eloqua
  class HttpClient
    def initialize(url)
      @url = url
    end

    delegate :get, :post, to: :connection

    private

    attr_reader :url

    def connection
      @connection ||= Faraday.new(url: url) do |builder|
        builder.use ::GitHub::FaradayMiddleware::RaiseError
        builder.use Faraday::Request::BasicAuthentication, "#{ENV.fetch("ELOQUA_SITENAME")}\\#{ENV.fetch("ELOQUA_USERNAME")}", ENV.fetch("ELOQUA_PASSWORD")

        builder.request :json
        builder.response :json, content_type: /\bjson\z/, parser_options: { symbolize_names: true }

        builder.adapter Faraday.default_adapter
      end
    end
  end
end
