# typed: strict
# frozen_string_literal: true

class McpOauth::FindOrCreateServerConfig
  sig do
    params(
      user: User,
      mcp_server_id: Integer,
      code_verifier: String,
      display_name: T.nilable(String)
    ).returns(McpServerConfig)
  end
  def self.call(user:, mcp_server_id:, code_verifier:, display_name:)
    Copilot::Helpers.with_write do
      McpServerConfig.find_or_initialize_by(user: user, mcp_server_id: mcp_server_id).tap do |config|
        config.update(
          code_verifier: code_verifier,
          display_name: display_name
        )
      end
    end
  end
end
