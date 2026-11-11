# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_settings_client"

class Businesses::AiControls::McpLocalServerBlockController < Businesses::BusinessController
  include Businesses::CopilotShared
  include Businesses::AiControls::McpAllowlistFeatureFlag

  before_action :ensure_not_standalone_copilot_business
  before_action :require_ai_controls_enabled
  before_action :ai_controls_write_required
  before_action :ensure_allowlist_feature_flag_enabled
  before_action :validate_block_local_servers_value

  sig { void }
  def create
    McpRegistry::EnterpriseSettingsClient.update_settings(
      enterprise_id: this_business.id,
      block_local_servers: @block_local_servers_value,
      token: mcp_registry_token,
    )
    head :ok
  rescue StandardError => e
    logger.error("MCP_Registry_Enterprise_Error: Failed to update MCP settings for business #{this_business.id}: #{e.class}: #{e.message}")
    status = http_status_for(e)
    render plain: error_message_for(e), status:
  end

  private

  sig { void }
  def require_ai_controls_enabled
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def validate_block_local_servers_value
    value = params.require(:value)
    case value
    when "1"
      @block_local_servers_value = T.let(true, T.nilable(T::Boolean))
    when "0"
      @block_local_servers_value = T.let(false, T.nilable(T::Boolean))
    else
      render plain: "Something went wrong. Please try again.", status: :unprocessable_entity
    end
  rescue ActionController::ParameterMissing
    render plain: "Something went wrong. Please try again.", status: :unprocessable_entity
  end

  sig { returns(String) }
  def mcp_registry_token
    current_user.signed_auth_token(
      scope: McpRegistry::EnterpriseSettingsClient::MCP_REGISTRY_TOKEN_SCOPE,
      expires: 5.minutes.from_now,
    )
  end

  sig { params(err: StandardError).returns(Symbol) }
  def http_status_for(err)
    if err.is_a?(McpRegistry::EnterpriseSettingsClient::ApiError)
      case err.status
      when 401 then :unauthorized
      when 403 then :forbidden
      when 404 then :not_found
      when 422 then :unprocessable_entity
      end
    end || :internal_server_error
  end

  sig { params(err: StandardError).returns(String) }
  def error_message_for(err)
    if err.is_a?(McpRegistry::EnterpriseSettingsClient::ApiError)
      return "You don't have permission to perform this action." if err.status == 401 || err.status == 403
    end
    "Something went wrong. Please try again."
  end
end
