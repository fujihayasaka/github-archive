# typed: true
# frozen_string_literal: true

class Copilot::Mcp::ServersController < ApplicationController
  include Copilot::Mcp::ControllerMethods
  before_action :login_required
  before_action :feature_flag_required
  before_action :validate_params, only: :create

  def create
    server_url = params[:mcp_server_url]
    mcp_server = McpOauth::FindOrRegisterMcpServer.call(
      server_url: server_url
    )

    GitHub.logger.info(
      "MCP server registered",
      "code.namespace": "Copilot::Mcp::ServersController",
      "code.function": "create",
      "gh.actor.id": current_user&.id,
      "gh.request_id": request_id,
    )

    redirect_to mcp_authorization_new_path(mcp_server_id: mcp_server.id), notice: "Client registered successfully"
  rescue McpOauth::ServerRegistrationError => e
    GitHub.logger.error("MCP client registration failed", "exception.message": e.full_message, "exception.type": e.class.name)
    render plain: "Client setup failed", status: :bad_request
  end

  private

  def validate_params
    head :bad_request unless params[:mcp_server_url].present?
  end

  def feature_flag_required
    render_404 unless current_user&.feature_enabled?(:copilot_mcp)
  end
end
