# typed: true
# frozen_string_literal: true

module GitHubModels
  class ApiClient
    extend T::Helpers

    class ApiError < StandardError; end

    abstract!

    sig do
      params(api_url: String, service_name: String, internal_client: T::Boolean, hmac_key: T.nilable(String)).void
    end
    def initialize(api_url:, service_name:, internal_client: false, hmac_key: nil)
      @connection = new_connection(api_url, internal_client: internal_client, hmac_key: hmac_key)
      @service_name = service_name
    end

    protected

    sig { returns ::Faraday::Connection }
    attr_reader :connection

    sig { params(res: ::Faraday::Response, action: String).void }
    def handle_request_error(res, action:)
      return if res.status == 200 || res.success?

      json = if res.body.present?
        begin
          JSON.parse(res.body)
        rescue JSON::ParserError
          {}
        end
      else
        {}
      end

      error_message = json.dig("error", "message")
      suffix = error_message.present? ? ": #{error_message}" : ""
      raise ApiError.new("Error #{action} from #{@service_name} service using URL #{connection.url_prefix} " \
        "(HTTP #{res.status})#{suffix}")
    end

    sig { params(res: ::Faraday::Response).returns(T.untyped) }
    def parse_response_json(res:)
      JSON.parse(res.body)
    rescue JSON::ParserError
      msg = "There was an error parsing the response from the #{@service_name} service using " \
        "URL #{connection.url_prefix}"
      raise ApiError.new(msg)
    end

    private

    sig do
      params(url: String, internal_client: T::Boolean, hmac_key: T.nilable(String)).returns(::Faraday::Connection)
    end
    def new_connection(url, internal_client:, hmac_key:)
      client_class = internal_client ? ::GitHub::FaradayClient::Internal : ::GitHub::FaradayClient::External
      client_class.new(url) do |conn|
        conn.options[:open_timeout] = internal_client ? 10 : 2
        conn.options[:timeout] = 5
        conn.headers[:content_type] = "application/json"

        if internal_client
          conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
        end

        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats,
          service_name: GitHub::Config::Models::SERVICE_NAME
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: GitHub::Config::Models::SERVICE_NAME
        conn.use(::GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key) if hmac_key
        conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2

        conn.adapter :typhoeus
      end
    end
  end
end
