# typed: strict
# frozen_string_literal: true

module McpOauth
  # Centralized cleanup for MCP OAuth records:
  # - Remove McpServerConfig records that failed auth (no access token).
  # - Remove orphaned McpServer records with no remaining configs.
  class Cleanup
    NAMESPACE = T.let("McpOauth::Cleanup".freeze, String)

    # Remove a config that failed authentication (no access_token).
    # Returns true when destroyed, false if destroy was blocked.
    sig { params(config: McpServerConfig, reason: String).returns(T::Boolean) }
    def self.remove_failed_config(config, reason = "failed MCP server config after authentication failure")
      config_id = config.id
      server_id = config.mcp_server_id

      if config.access_token.present?
        GitHub.logger.info(
          "Skipped removal: config has access token",
          "code.namespace": NAMESPACE,
          "code.function": "remove_failed_config",
          "gh.copilot.mcp.config_id": config_id,
          "gh.copilot.mcp.server_id": server_id
        )
        return false
      end

      begin
        config.destroy!
        GitHub.logger.info(
          "Removed #{reason}",
          "code.namespace": NAMESPACE,
          "code.function": "remove_failed_config",
          "gh.copilot.mcp.config_id": config_id,
          "gh.copilot.mcp.server_id": server_id
        )
        true
      rescue ActiveRecord::RecordNotDestroyed => e
        GitHub.logger.error(
          "Failed to remove #{reason}",
          "code.namespace": NAMESPACE,
          "code.function": "remove_failed_config",
          "error.class": e.class.name,
          "error.message": e.message,
          "gh.copilot.mcp.config_id": config_id,
          "gh.copilot.mcp.server_id": server_id
        )
        false
      end
    end

    # Remove the server if it has no remaining configs.
    sig { params(server: McpServer).void }
    def self.remove_unused_server(server)
      return if server.mcp_server_configs.exists?

      server_id = server.id
      begin
        server.destroy!
        GitHub.logger.info(
          "Removed unused MCP server with no remaining configs",
          "code.namespace": NAMESPACE,
          "code.function": "remove_unused_server",
          "gh.copilot.mcp.server_id": server_id
        )
      rescue ActiveRecord::RecordNotDestroyed => e
        GitHub.logger.error(
          "Failed to remove unused MCP server",
          "code.namespace": NAMESPACE,
          "code.function": "remove_unused_server",
          "error.class": e.class.name,
          "error.message": e.message,
          "gh.copilot.mcp.server_id": server_id
        )
      end
    end
  end
end
