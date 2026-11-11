# typed: strict
# frozen_string_literal: true

# Shared before_action filters and helpers used by MCP allowlist controllers.
module Businesses::AiControls::McpAllowlistShared
  extend T::Helpers
  extend ActiveSupport::Concern

  include Businesses::AiControls::McpAllowlistFeatureFlag

  requires_ancestor { Businesses::BusinessController }

  private

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  MCP_REGISTRY_TOKEN_SCOPE = "mcp_registry"

  sig { returns(String) }
  def mcp_registry_token
    current_user.signed_auth_token(
      scope: MCP_REGISTRY_TOKEN_SCOPE,
      expires: 5.minutes.from_now,
    )
  end
end
