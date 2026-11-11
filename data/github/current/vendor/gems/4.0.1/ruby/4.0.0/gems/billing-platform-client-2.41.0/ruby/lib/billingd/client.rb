# frozen_string_literal: true

require_relative "../billing-platform/version"
require_relative "../billing-platform/twirp/hmac/request_signing_middleware"

require_relative "../proto/billingcore-subscription-api_pb"
require_relative "../proto/billingcore-subscription-api_twirp"

module Billingd
  class Client
    attr_reader :subscriptions

    def initialize(host: nil, path_prefix: "twirp", hmac_key:, &blk)
      @host = host || default_host_mapping[inferred_env] || default_host_mapping[:development]
      @url = [@host.chomp("/"), *path_prefix.split("/").reject { |s| s.nil? || s == "" }].join("/")
      @hmac_key = hmac_key

      connection = setup_default_connection(&blk)
      @subscriptions = BillingCore::Subscription::V1::SubscriptionAPIClient.new(connection)
    end

    private

    attr_reader :url

    def inferred_env
      if !ENV["HEAVEN_DEPLOYED_ENV"].nil?
        return :production if ENV["HEAVEN_DEPLOYED_ENV"].match?(/\A(?:production|prod|review-lab)\b/)
        return :staging if ENV["HEAVEN_DEPLOYED_ENV"].match?(/\Astaging\b/)
      end
      env = ENV.fetch("RAILS_ENV") { ENV.fetch("RACK_ENV", "development") }
      env.to_sym
    end

    def default_host_mapping
      @default_host_mapping ||= {
        development: "http://localhost:8990",
        staging: "https://billingd-staging.service.iad.github.net",
        production: "https://billingd-production.service.iad.github.net",
      }
    end

    def setup_default_connection(&blk)
      Faraday.new(url: url) do |conn|
        configure_connection(conn, &blk)
        conn.adapter Faraday.default_adapter
      end
    end

    def configure_connection(conn, &blk)
      conn.headers = conn.headers.merge(default_headers)
      conn.use BillingPlatform::Twirp::HMAC::RequestSigningMiddleware, @hmac_key
      yield(conn) if blk
      conn
    end

    def default_headers
      @default_headers ||= { "User-Agent" => "Billingd client v#{BillingPlatform::VERSION}" }
    end
  end
end
