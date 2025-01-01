# typed: true
# frozen_string_literal: true

module Codespaces
  # Public: Interface to the VSCS backend, without an associated plan.
  class AnonymousVscsClient < Client
    attr_reader :api_url

    def initialize(api_url:, **kwargs)
      @api_url = api_url
      super **kwargs
    end

    def get(path)
      resp = vscs_connection.get(path, {}, { "Content-Type" => "application/json" })
    rescue Faraday::TimeoutError
      raise TimeoutError, request_err_message("Timeout exceeded", :get)
    rescue Faraday::ConnectionFailed => e
      raise ConnectionFailed, request_err_message("Connection failed: #{e.message}", :get)
    end

    def get_json(path)
      resp = get(path)
      unless resp.success?
        error_body = resp.body
        begin
          error_body = GitHub::JSON.parse(resp.body)
        rescue Yajl::ParseError
        end
        raise BadResponseError.new(request_err_message("Bad response", :get), resp.status, error_body)
      end
      GitHub::JSON.parse(resp.body)
    rescue Yajl::ParseError
      raise BadResponseError, request_err_message("Bad response", :get, "invalid JSON")
    end

    private

    def vscs_connection
      @vscs_connection ||= connection_for(api_url) do |f|
        f.use Codespaces::FollowVsoRedirects
      end
    end
  end
end
