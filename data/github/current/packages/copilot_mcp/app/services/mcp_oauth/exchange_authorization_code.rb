# typed: strict
# frozen_string_literal: true

class McpOauth::ExchangeAuthorizationCode
  class TokenExchangeError < StandardError; end

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
      code: String,
      client_id: String,
      client_secret: String,
      code_verifier: String
    ).returns(TokenResponse)
  end
  def self.call(server_url:, code:, client_id:, client_secret:, code_verifier:)
    body = {
      code: code,
      client_id: client_id,
      client_secret: client_secret,
      code_verifier: code_verifier,
      grant_type: "authorization_code"
    }

    if use_authorization_header(server_url)
      authorization = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      body = body.merge(
        redirect_uri: McpOauth::Configuration.redirect_uri,
      )
    end

    response = McpOauth::HttpClient.post(
      token_endpoint_for(server_url),
      body,
      content_type: "application/x-www-form-urlencoded",
      authorization: use_authorization_header(server_url) ? authorization : nil
    )

    raise TokenExchangeError, "Token exchange failed: #{response.status}" unless response.status == 200

    parse_token_response(response.body)
  end

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

  sig { params(body: String).returns(TokenResponse) }
  def self.parse_token_response(body)
    parsed = GitHub::JSON.parse(body)

    {
      access_token: T.let(parsed["access_token"], String),
      token_type: T.let(parsed["token_type"], String),
      expires_in: T.let(parsed["expires_in"], Integer),
      scope: parsed["scope"],
      refresh_token: T.let(parsed["refresh_token"], String),
    }
  end
  private_class_method :parse_token_response
end
