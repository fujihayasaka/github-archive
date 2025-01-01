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

      token_data = ExchangeAuthorizationCode.call(
        server_url: server_url,
        code: code,
        client_id: client_id,
        client_secret: client_secret,
        code_verifier: config.code_verifier
      )

      update_tokens!(config, token_data)
    end

    sig { params(config: McpServerConfig, token_data: T::Hash[Symbol, T.untyped]).returns(McpServerConfig) }
    def self.update_tokens!(config, token_data)
      Copilot::Helpers.with_write do
        config.update!(
          access_token: token_data[:access_token],
          refresh_token: token_data[:refresh_token],
          access_token_expires_at: Time.current + token_data[:expires_in].to_i.seconds
        )
      end

      config
    end
    private_class_method :update_tokens!
  end
end
