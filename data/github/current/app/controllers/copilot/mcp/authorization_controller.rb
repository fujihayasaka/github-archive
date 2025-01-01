# typed: true
# frozen_string_literal: true

class Copilot::Mcp::AuthorizationController < ApplicationController
  include Copilot::Mcp::ControllerMethods
  before_action :login_required
  before_action :feature_flag_required

  def new
    mcp_server = CopilotMcp.find_mcp_server(params.require(:mcp_server_id).to_i)

    auth_url = McpOauth::BuildAuthorizationUrl.call(
      user: current_user,
      server_url: T.must(mcp_server.url),
      client_id: T.must(mcp_server.oauth_client_id),
      mcp_server_id: T.must(mcp_server.id),
      return_url: return_url
    )

    redirect_to auth_url
  end

  def create
    config_id = mcp_server_config_id
    raise ActionController::ParameterMissing, "mcp_server_config_id" unless config_id.present?

    config = CopilotMcp.find_mcp_server_config(config_id, current_user)
    mcp_server = CopilotMcp.find_mcp_server(config.mcp_server_id)

    McpOauth::AuthorizeUserForMcpServer.call(
      code: params.require(:code),
      user: current_user,
      client_id: T.must(mcp_server.oauth_client_id),
      client_secret: T.must(mcp_server.oauth_client_secret),
      server_url: T.must(mcp_server.url),
      mcp_server_config_id: config.id
    )

    GitHub.logger.info(
      "MCP OAuth token received",
      "code.namespace": "Copilot::Mcp::AuthorizationController",
      "code.function": "create",
      "gh.actor.id": current_user&.id,
      "gh.request_id": request_id
    )

    if return_url.present?
      redirect_to return_url
    else
      # TODO: maybe redirect to a different page
      redirect_to mcp_settings_path, notice: "MCP connected"
    end
  end

  private

  sig { returns(T.nilable(String)) }
  def return_url
    return_url = URI.parse(state[:return_url])
    return nil unless return_url.relative?
    return_url.to_s
  rescue URI::InvalidURIError
    nil
  end

  sig { returns(T.nilable(Integer)) }
  def mcp_server_config_id
    state[:mcp_server_config_id].to_i
  end

  memoize def state
    if params[:state].present?
      McpOauth::State.parse(params[:state])
    else
      params
    end
  end

  def feature_flag_required
    render_404 unless current_user&.feature_enabled?(:copilot_mcp) || current_user&.feature_enabled?(:copilot_immersive_figma_integration)
  end
end
