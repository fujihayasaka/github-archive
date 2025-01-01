# typed: true
# frozen_string_literal: true

class Copilot::Mcp::AuthorizationController < ApplicationController
  include Copilot::Mcp::ControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot

  before_action :login_required
  before_action :feature_flag_required

  def new
    # Load MCP server
    mcp_server = CopilotMcp::Query.find_mcp_server(params.require(:mcp_server_id).to_i)
    display_name = params[:display_name].to_s.presence || mcp_server.name

    # Generate PKCE pair for this authorization request
    pair = McpOauth::PkcePair.generate

    # Create or update server config with PKCE code_verifier and display_name
    mcp_server_config = McpOauth::FindOrCreateServerConfig.call(
      user: current_user,
      mcp_server_id: mcp_server.id,
      code_verifier: pair.code_verifier,
      display_name: display_name
    )
    unless mcp_server_config.valid?
      render json: {
        field_errors: mcp_server_config.errors.as_json(full_messages: true),
      }, status: :unprocessable_entity
      return
    end

    # Build authorization URL for OAuth redirect
    auth_url = McpOauth::BuildAuthorizationUrl.call(
      mcp_server_config_id: mcp_server_config.id,
      server_url: mcp_server.url,
      client_id: mcp_server.oauth_client_id,
      code_challenge: pair.code_challenge,
      return_url: params.require(:return_url)
    )
    respond_to do |format|
      format.json { render json: { redirect_url: auth_url } }
      format.html do
        safe_redirect_to auth_url,
        allow_hosts: Copilot::ChatLinkItem::ALLOWED_FIGMA_HOSTS,
        allow_query: true
      end
    end
  end

  def create
    config_id = mcp_server_config_id
    raise ActionController::ParameterMissing, "mcp_server_config_id" unless config_id.present?

    config = CopilotMcp::Query.find_mcp_server_config!(config_id, current_user)
    mcp_server = CopilotMcp::Query.find_mcp_server(config.mcp_server_id)
    context = session[:mcp_context] || context_from_referer
    begin
      McpOauth::AuthorizeUserForMcpServer.call(
        code: params.require(:code),
        user: current_user,
        client_id: T.must(mcp_server.oauth_client_id),
        client_secret: T.must(mcp_server.oauth_client_secret),
        server_url: T.must(mcp_server.url),
        mcp_server_config_id: config.id
      )

      Hydro::McpServerEventsPublisher.publish_success(
        action: :authorize,
        server: mcp_server,
        user: current_user,
        context: context,
      )

      GitHub.logger.info(
        "MCP OAuth token received",
        "code.namespace": "Copilot::Mcp::AuthorizationController",
        "code.function": "create",
        "gh.actor.id": current_user&.id,
        "gh.request_id": request_id
      )

      # Redirect to the original return URL
      safe_redirect_to return_url, notice: "MCP connected"
    rescue McpOauth::Errors::TokenExchangeError => e
      handle_mcp_authorize_error(e, mcp_server, config, context, "MCP token exchange failed", "Failed to connect to MCP server. Please try again.")

    rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
      handle_mcp_authorize_error(e, mcp_server, config, context, "MCP connection failed", "Unable to connect to MCP server. Please check your network connection.")

    rescue Faraday::Error => e
      handle_mcp_authorize_error(e, mcp_server, config, context, "MCP HTTP error", "Failed to communicate with MCP server. Please try again.")

    ensure
      # Clean up temporary session data used to preserve user's original context across OAuth redirect flow
      session.delete(:mcp_context)
    end
  end

  private

  sig { returns(String) }
  def return_url
    # Extract return_url from state (passed through OAuth redirect flow)
    state[:return_url].to_s.strip
  end

  def log_mcp_error(message, error)
    log_data = {
      "code.namespace": "Copilot::Mcp::AuthorizationController",
      "code.function": "create",
      "error.class": error.class.name,
      "error.message": error.message,
      "gh.actor.id": current_user&.id,
      "gh.request_id": request_id,
    }

    log_data["error.backtrace"] = error.backtrace if error.backtrace

    GitHub.logger.error(message, log_data)
  end

  sig { returns(T.nilable(Integer)) }
  def mcp_server_config_id
    state[:mcp_server_config_id].to_i
  end

  memoize def state
    if params[:state].present?
      begin
        return McpOauth::State.decode(params[:state])
      rescue JWT::VerificationError => e
        GitHub.logger.error(
          "MCP state JWT verification error",
          "code.namespace": "Copilot::Mcp::AuthorizationController",
          "code.function": "state",
          "error.class": e.class.name,
          "error.message": e.message,
          "gh.actor.id": current_user&.id,
          "gh.request_id": request_id
        )
      rescue JWT::DecodeError => e
        GitHub.logger.error(
          "MCP state JWT decode error",
          "code.namespace": "Copilot::Mcp::AuthorizationController",
          "code.function": "state",
          "error.class": e.class.name,
          "error.message": e.message,
          "gh.actor.id": current_user&.id,
          "gh.request_id": request_id
        )
      end
    end

    # Fallback to params for initial requests (before OAuth redirect)
    params
  end

  def redirect_with_error_message(message)
    safe_redirect_to return_url, flash: { error: message }
  end

  def handle_mcp_authorize_error(error, mcp_server, config, context, log_message, user_message)
    Hydro::McpServerEventsPublisher.publish_error(
      action: :authorize,
      server: mcp_server,
      user: current_user,
      context: context,
      error: error
    )

    # Log error for debugging
    log_mcp_error(log_message, error)

    # Clean up failed config that has been initialized and left in an incomplete state
    cleanup_failed_config(config)

    # Redirect with user-friendly message
    redirect_with_error_message(user_message)
  end

  def feature_flag_required
    render_404 unless current_user&.feature_flag_enabled?(:copilot_api_dotcom_chat_use_third_party_mcp_servers, default: false) || current_user&.feature_flag_enabled?(:copilot_immersive_figma_integration, default: false)
  end

  # Remove failed MCP server config records when OAuth auth fails
  # (prevents accumulation of configs without valid access tokens)
  def cleanup_failed_config(config)
    McpOauth::Cleanup.remove_failed_config(config)
  rescue StandardError => e # rubocop:disable Lint/RescueException, Lint/GenericRescue
    GitHub.logger.error(
      "Failed to clean up MCP server config after authentication failure",
      "code.namespace": "Copilot::Mcp::AuthorizationController",
      "code.function":  "cleanup_failed_config",
      "error.class":    e.class.name,
      "error.message":  e.message,
      "gh.actor.id":    current_user&.id,
      "gh.request_id":  request_id
    )
  end
end
