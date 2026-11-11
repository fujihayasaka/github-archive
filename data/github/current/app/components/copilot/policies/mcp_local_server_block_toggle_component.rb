# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_settings_client"

module Copilot
  module Policies
    class McpLocalServerBlockToggleComponent < McpBaseComponent
      sig { void }
      def before_render
        # Eagerly fetch settings so @settings_fetch_error is set
        # before the template checks it.
        block_local_servers_enabled?
      end

      sig { returns(String) }
      def mcp_registry_token
        current_user.signed_auth_token(
          scope: ::McpRegistry::EnterpriseSettingsClient::MCP_REGISTRY_TOKEN_SCOPE,
          expires: 5.minutes.from_now,
        )
      end

      sig { returns(T::Boolean) }
      def block_local_servers_enabled?
        return !!@block_local_servers_enabled unless @block_local_servers_enabled.nil?

        settings = ::McpRegistry::EnterpriseSettingsClient.get_settings(
          enterprise_id: @configurable.id,
          token: mcp_registry_token,
        )
        @block_local_servers_enabled = T.let(
          settings["block_local_servers"] == true,
          T.nilable(T::Boolean),
        )
        !!@block_local_servers_enabled
      rescue StandardError => e
        Rails.logger.error("MCP_Registry_Enterprise_Error: Failed to fetch MCP settings for business #{@configurable.id}: #{e.message}")
        @settings_fetch_error = T.let(true, T.nilable(T::Boolean))
        @block_local_servers_enabled = T.let(false, T.nilable(T::Boolean))
        false
      end

      sig { returns(T::Boolean) }
      def settings_fetch_error?
        @settings_fetch_error ||= T.let(false, T.nilable(T::Boolean))
        !!@settings_fetch_error
      end

      sig { returns(String) }
      def block_source_path
        mcp_local_server_block_enterprise_ai_controls_enterprise_path(@configurable)
      end

      sig { returns(String) }
      def block_csrf_token
        authenticity_token_for(block_source_path)
      end
    end
  end
end
