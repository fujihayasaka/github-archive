# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_settings_client"

class Copilot::SyncMcpRegistryPolicyJob < CopilotJob
  queue_as :copilot
  retry_on_dirty_exit

  resolve_tenant_context do |business_id, _mcp_policy, _user_id|
    ::Business.find_by(id: business_id)
  end

  sig { params(business_id: Integer, mcp_policy: String, user_id: Integer).void }
  def perform(business_id, mcp_policy, user_id)
    GitHub.logger.with_named_tags(
      "gh.business.id" => business_id,
      "gh.copilot.mcp_policy" => mcp_policy,
    ) do
      user = ::User.find_by(id: user_id)
      unless user
        GitHub.logger.warn("MCP_Registry_Enterprise_Error: User #{user_id} not found, skipping MCP policy sync")
        return
      end

      token = user.signed_auth_token(
        scope: McpRegistry::EnterpriseSettingsClient::MCP_REGISTRY_TOKEN_SCOPE,
        expires: 5.minutes.from_now,
      )

      McpRegistry::EnterpriseSettingsClient.update_settings(
        enterprise_id: business_id,
        mcp_policy: mcp_policy,
        token: token,
      )

      GitHub.logger.info("MCP_Registry_Enterprise: Successfully synced mcp_policy=#{mcp_policy} for business #{business_id}")
    rescue McpRegistry::EnterpriseSettingsClient::ApiError => e
      GitHub.logger.error("MCP_Registry_Enterprise_Error: Failed to sync MCP policy for business #{business_id}: #{e.status} #{e.message}")
      raise if e.status >= 500
    rescue StandardError => e
      GitHub.logger.error("MCP_Registry_Enterprise_Error: Failed to sync MCP policy for business #{business_id}: #{e.class}: #{e.message}")
      raise
    end
  end
end
