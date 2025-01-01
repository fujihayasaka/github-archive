# typed: strict
# frozen_string_literal: true

# McpOauth::State is responsible for encoding and decoding the state parameter used in OAuth flows.
# It uses JWT (JSON Web Tokens) to securely(not encrypted!) encode the state information, which includes
# the mcp_server_config_id and an optional return_url.
#
# JWT is used so that we can verify the state parameter that is included in the request
# callback from the authorization server has not been modified externally.
#
class McpOauth::State

  # Token expiration time in seconds (15 minutes)
  TOKEN_EXPIRATION = T.let(15 * 60, Integer)

  # Clock skew tolerance in seconds (5 minutes)
  CLOCK_SKEW_TOLERANCE = T.let(5 * 60, Integer)

  sig { returns(NilClass) }
  def self.verify_secret_present
    if !GitHub.copilot_api_mcp_oauth_jwt_hs512_token.present?
      raise RuntimeError, "copilot_api_mcp_oauth_jwt_hs512_token Vault backed variable is not set, it must be set to a non-empty string."
    end
  end

  sig { params(state: String).returns(T::Hash[Symbol, T.untyped]) }
  def self.decode(state)
    self.verify_secret_present
    options = {
      algorithm: "HS512",
      leeway: CLOCK_SKEW_TOLERANCE
    }
    payload, _ = JWT.decode(state, GitHub.copilot_api_mcp_oauth_jwt_hs512_token, true, options)
    payload = payload.symbolize_keys
  end

  # Encodes the state in a signed JWT token.
  sig { params(mcp_server_config_id: Integer, return_url: String).returns(String) }
  def self.encode(mcp_server_config_id, return_url)
    self.verify_secret_present
    now = Time.current.to_i

    payload = {
      mcp_server_config_id: mcp_server_config_id,
      return_url: return_url,
      iat: now,           # Issued at time
      nbf: now,           # Not before time (valid from now)
      exp: now + TOKEN_EXPIRATION  # Expiration time
    }

    token = JWT.encode(payload, GitHub.copilot_api_mcp_oauth_jwt_hs512_token, "HS512")
  end
end
