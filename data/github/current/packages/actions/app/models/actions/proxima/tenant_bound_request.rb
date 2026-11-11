# typed: true
# frozen_string_literal: true

class Actions::Proxima::TenantBoundRequest
  sig { returns(DotcomClient) }
  def self.dotcom
    @dotcom ||= DotcomClient.new
  end

  class DotcomClient
    def initialize(api_base_url: nil)
      @api_base_url = api_base_url || "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_api_host_name}"
    end

    sig { params(logins: T::Array[String]).returns(T::Array[String]) }
    def actions_verified_owners(logins)
      response = connection.post do |req|
        req.url "/marketplace/actions/verified_owners"
        req.headers["X-GitHub-PSI-JWT"] = generate_token
        req.body = { logins: }
      end

      unless response.success?
        raise Actions::Proxima::Errors::ActionsVerifiedOwnersError.new("http request failed",
          url: response.env.url,
          status: response.status,
          body: response.body,
        )
      end

      response.body["verified_logins"] || []
    rescue Faraday::ParsingError => e
      raise Actions::Proxima::Errors::ActionsVerifiedOwnersError.new("malformed response body",
        url: e.response.env.url,
        status: e.response.status,
        body: e.response.body,
        errors: [e.message]
      )
    end

    def actions_resolve(nwo:, ref:)
      token = generate_token

      response = connection.get do |req|
        req.url "/repos/#{nwo}/actions/resolve/#{ref}"
        req.headers["X-GitHub-PSI-JWT"] = token
      end

      unless response.success? || [404, 422].include?(response.status)
        raise Actions::Proxima::Errors::ActionsResolveError.new("http request failed",
          url: response.env.url,
          status: response.status,
          body: response.body,
        )
      end

      if response.success?
        response.body["proxima_service_identity_token"] = token
      end

      response
    end

    private

    sig { returns(String) }
    def generate_token
      @token_generator ||= Actions::Proxima::TokenGenerator.new
      @token_generator.generate_proxima_service_identity_token
    end

    sig { returns(Faraday::Connection) }
    def connection
      @connection ||= GitHub::FaradayClient::External.new(
        url: @api_base_url,
      ) do |conn|
        conn.adapter Faraday.default_adapter
        conn.request :json
        conn.response :json
      end
    end
  end
end
