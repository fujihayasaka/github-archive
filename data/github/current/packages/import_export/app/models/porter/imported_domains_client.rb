# typed: true
# frozen_string_literal: true

module Porter
  class ImportedDomainsClient
    include Porter::Urls

    def initialize(internal_api_token: GitHub.porter_internal_api_token, timeout: 1)
      @auth_token = internal_api_token
      @timeout    = timeout
    end

    attr_reader :auth_token, :timeout

    private

    def faraday
      @faraday ||= build_faraday
    end

    def build_faraday
      options = {
        headers: {
          "Accept" => "application/vnd.porter.v1+json",
        },
        request: {
          timeout: timeout,
          open_timeout: 5,
        },
      }
      Faraday.new(options) do |c|
        c.basic_auth(auth_token, "github")
        c.adapter Faraday.default_adapter
      end
    end
  end
end
