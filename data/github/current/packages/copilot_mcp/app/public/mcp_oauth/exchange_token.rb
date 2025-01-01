# typed: strict
# frozen_string_literal: true

module McpOauth
  class ExchangeToken
    TokenResponse = T.type_alias do
      {
        access_token: String,
        token_type: String,
        expires_in: Integer,
        scope: T.nilable(String),
        refresh_token: String
      }
    end

    sig do
      params(
        server_url: String,
        client_id: String,
        client_secret: String,
        code: String,
        code_verifier: String
      ).returns(TokenResponse)
    end
    def self.from_code(server_url:, client_id:, client_secret:, code:, code_verifier:)
      body = {
        grant_type: "authorization_code",
        client_id: client_id,
        client_secret: client_secret,
        code: code,
        code_verifier: code_verifier
      }

      if use_authorization_header(server_url)
        body = body.merge(redirect_uri: McpOauth::Configuration.redirect_uri)
        authorization = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      else
        authorization = nil
      end

      make_token_request(server_url: server_url, body: body, authorization: authorization)
    end

    sig do
      params(
        server_url: String,
        client_id: String,
        client_secret: String,
        refresh_token: String
      ).returns(TokenResponse)
    end
    def self.from_refresh_token(server_url:, client_id:, client_secret:, refresh_token:)
      body = {
        grant_type: "refresh_token",
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: refresh_token
      }

      make_token_request(server_url: server_url, body: body, authorization: nil)
    end

    private

    sig do
      params(
        server_url: String,
        body: T::Hash[Symbol, String],
        authorization: T.nilable(String)
      ).returns(TokenResponse)
    end
    def self.make_token_request(server_url:, body:, authorization:)
      token_endpoint = token_endpoint_for(server_url)

      response = McpOauth::HttpClient.post(
        token_endpoint,
        body,
        content_type: "application/x-www-form-urlencoded",
        authorization: authorization
      )

      unless response.success?
        raise McpOauth::Errors::TokenExchangeError, "Token exchange failed"
      end

      parse_token_response(response.body)
    end
    private_class_method :make_token_request

    sig { params(server_url: String).returns(T::Hash[Symbol, T.untyped]) }
    def self.metadata(server_url)
      McpOauth::Router.new(server_url).metadata
    end
    private_class_method :metadata

    sig { params(server_url: String).returns(String) }
    def self.token_endpoint_for(server_url)
      metadata(server_url)[:token_endpoint]
    end
    private_class_method :token_endpoint_for

    sig { params(server_url: String).returns(T.nilable(T::Boolean)) }
    def self.use_authorization_header(server_url)
      metadata(server_url)[:use_authorization_header]
    end
    private_class_method :use_authorization_header

    sig { params(body: String).returns(TokenResponse) }
    def self.parse_token_response(body)
      parsed = GitHub::JSON.parse(body)

      {
        access_token: T.let(parsed["access_token"], String),
        token_type: T.let(parsed["token_type"], String),
        expires_in: T.let(parsed["expires_in"], Integer),
        scope: parsed["scope"],
        refresh_token: T.let(parsed["refresh_token"], String)
      }
    end
    private_class_method :parse_token_response
  end
end
