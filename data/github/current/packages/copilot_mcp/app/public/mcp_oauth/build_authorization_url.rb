# typed: strict
# frozen_string_literal: true

# rubocop:disable Style/WordArray

class McpOauth::BuildAuthorizationUrl
  sig do
    params(
      mcp_server_config_id: Integer,
      server_url: String,
      client_id: String,
      code_challenge: String,
      return_url: String
    ).returns(String)
  end
  def self.call(mcp_server_config_id:, server_url:, client_id:, code_challenge:, return_url:)
    metadata = McpOauth::Router.new(server_url).metadata
    authorization_endpoint = metadata[:authorization_endpoint]

    redirect_uri = McpOauth::Configuration.redirect_uri

    uri = URI.parse(authorization_endpoint)
    query = URI.decode_www_form(uri.query.to_s)
    query.append(
      ["response_type", "code"],
      ["client_id", client_id],
      ["redirect_uri", redirect_uri.to_s],
      ["code_challenge", code_challenge],
      ["code_challenge_method", "S256"],
      ["state", McpOauth::State.encode(mcp_server_config_id, return_url)]
    )
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end
end
