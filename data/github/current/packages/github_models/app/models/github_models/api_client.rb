# typed: true
# frozen_string_literal: true

module GitHubModels
  class ApiClient
    extend T::Helpers

    class ApiError < StandardError; end

    abstract!

    sig { params(api_url: String, service_name: String).void }
    def initialize(api_url:, service_name:)
      @connection = new_connection(api_url)
      @service_name = service_name
    end

    protected

    sig { returns ::GitHub::FaradayClient::External }
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
      raise ApiError.new("Error #{action} from #{@service_name} service (HTTP #{res.status})#{suffix}")
    end

    sig { params(res: ::Faraday::Response).returns(T.untyped) }
    def parse_response_json(res:)
      JSON.parse(res.body)
    rescue JSON::ParserError
      msg = "There was an error parsing the response from the #{@service_name} service"
      raise ApiError.new(msg)
    end

    private

    sig { params(url: String).returns(::GitHub::FaradayClient::External) }
    def new_connection(url)
      ::GitHub::FaradayClient::External.new(url) do |conn|
        conn.options[:open_timeout] = 2
        conn.options[:timeout] = 5
        conn.headers[:content_type] = "application/json"

        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: GitHub::Config::Models::SERVICE_NAME
        conn.adapter :typhoeus
      end
    end
  end
end
