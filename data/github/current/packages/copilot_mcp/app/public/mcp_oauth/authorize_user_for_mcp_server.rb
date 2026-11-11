# typed: strict
# frozen_string_literal: true

module McpOauth
  class AuthorizeUserForMcpServer
    sig do
      params(
        code: String,
        client_id: String,
        client_secret: String,
        server_url: String,
        mcp_server_config_id: Integer,
        user: ::User
      ).returns(McpServerConfig)
    end
    def self.call(code:, client_id:, client_secret:, server_url:, mcp_server_config_id:, user:)
      config = McpServerConfig.find_by!(id: mcp_server_config_id, user_id: user.id)

      token_data = ExchangeToken.from_code(
        server_url: server_url,
        code: code,
        code_verifier: config.code_verifier,
        client_id: client_id,
        client_secret: client_secret
      )

      config.update_tokens!(
        access_token: token_data[:access_token],
        refresh_token: token_data[:refresh_token],
        expires_in: token_data[:expires_in].to_i.seconds
      )

      # Record installation audit event after successful token exchange
      config.record_event!(:installed, user)

      config
    end
  end
end
