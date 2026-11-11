# typed: strict
# frozen_string_literal: true

# Centralised feature-flag gate for the MCP registry "Private MCP servers"
# (enterprise publishing) UI. Include this concern in any controller that
# needs to check or enforce the :private_mcp_server_publish_enterprise flag.
# The flag is considered enabled when it is turned on for *either* the
# enterprise or the current user.
module Businesses::AiControls::McpPrivateServersFeatureFlag
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Businesses::BusinessController }

  private

  sig { returns(T::Boolean) }
  def private_servers_feature_flag_enabled?
    this_business&.feature_flag_enabled?(:private_mcp_server_publish_enterprise, default: false) ||
      current_user&.feature_flag_enabled?(:private_mcp_server_publish_enterprise, default: false) ||
      false
  end

  sig { void }
  def ensure_private_servers_feature_flag_enabled
    render_404 unless private_servers_feature_flag_enabled?
  end
end
