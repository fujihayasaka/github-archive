# typed: strict
# frozen_string_literal: true

# Centralised feature-flag gate for the MCP registry enterprise allowlist UI.
# Include this concern in any controller that needs to check or enforce the
# :copilot_mcp_registry_enterprise_allowlist_ui flag. The flag is considered
# enabled when it is turned on for *either* the enterprise or the current user.
module Businesses::AiControls::McpAllowlistFeatureFlag
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Businesses::BusinessController }

  private

  sig { returns(T::Boolean) }
  def allowlist_feature_flag_enabled?
    this_business&.feature_flag_enabled?(:copilot_mcp_registry_enterprise_allowlist_ui, default: false) ||
      current_user&.feature_flag_enabled?(:copilot_mcp_registry_enterprise_allowlist_ui, default: false) ||
      false
  end

  sig { returns(T::Boolean) }
  def allowlist_name_validation_enabled?
    this_business&.feature_flag_enabled?(:copilot_mcp_allowlist_require_name_validation, default: false) ||
      current_user&.feature_flag_enabled?(:copilot_mcp_allowlist_require_name_validation, default: false) ||
      false
  end

  sig { void }
  def ensure_allowlist_feature_flag_enabled
    render_404 unless allowlist_feature_flag_enabled?
  end
end
