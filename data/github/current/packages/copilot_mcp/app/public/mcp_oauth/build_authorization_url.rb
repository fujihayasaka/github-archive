# typed: strict
# frozen_string_literal: true

# rubocop:disable Style/WordArray

class McpOauth::BuildAuthorizationUrl
  sig do
    params(
      user: User,
      server_url: String,
      client_id: String,
      mcp_server_id: Integer,
      return_url: T.nilable(String)
    ).returns(String)
  end
  def self.call(user:, server_url:, client_id:, mcp_server_id:, return_url:)
    pair = McpOauth::PkcePair.generate

    mcp_server_config = Copilot::Helpers.with_write do
      config = McpServerConfig.find_or_initialize_by(
        user: user,
        mcp_server_id: mcp_server_id
      )

      config.update!(
        code_verifier: pair.code_verifier
      )
      config
    end
    metadata = McpOauth::Router.new(server_url).metadata

    redirect_uri = McpOauth::Configuration.redirect_uri
    build_authorization_url(
      mcp_server_config_id: mcp_server_config.id,
      authorization_endpoint: metadata[:authorization_endpoint],
      client_id: client_id,
      redirect_uri: redirect_uri,
      code_challenge: pair.code_challenge,
      return_url: return_url
    )
  end

  sig do
    params(
      mcp_server_config_id: Integer,
      authorization_endpoint: String,
      client_id: String,
      redirect_uri: String,
      code_challenge: String,
      return_url: T.nilable(String)
    ).returns(String)
  end
  def self.build_authorization_url(mcp_server_config_id:, authorization_endpoint:, client_id:, redirect_uri:, code_challenge:, return_url:)
    uri = URI.parse(authorization_endpoint)
    query = URI.decode_www_form(uri.query.to_s)
    query.append(
      ["response_type", "code"],
      ["client_id", client_id],
      ["redirect_uri", redirect_uri.to_s],
      ["code_challenge", code_challenge],
      ["code_challenge_method", "S256"],
      ["state", McpOauth::State.build(mcp_server_config_id, return_url)]
    )
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end
  private_class_method :build_authorization_url
end
