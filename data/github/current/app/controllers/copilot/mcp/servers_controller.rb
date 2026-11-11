# typed: true
# frozen_string_literal: true

class Copilot::Mcp::ServersController < ApplicationController
  include Copilot::Mcp::ControllerMethods
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    only: [:index]

  allow_verified_fetch only: [:create]
  before_action :login_required
  before_action :feature_flag_required
  before_action :validate_params, only: :create

  PER_PAGE = 10

  def index
    servers = CopilotMcp::Query.search_mcp_server_configs_for_user(current_user, name: params[:server_name].presence)
    paginated_servers = servers.paginate(page: current_page, per_page: PER_PAGE)

    respond_to do |format|
      format.json do
        render json: {
          servers: paginated_servers.map do |config|
            {
              id: config.id,
              text: config.mcp_server&.name,
              display_name: config.display_name,
              description: config.mcp_server&.url
            }
          end,
          total_count: paginated_servers.total_entries,
          page: current_page,
          total_pages: paginated_servers.total_pages
        }
      end
    end
  end

  def create
    server_url = params[:mcp_server_url]
    server_name = params[:name]

    begin
      mcp_server = McpOauth::FindOrRegisterMcpServer.call(
        server_url: server_url
      )

      Hydro::McpServerEventsPublisher.publish_success(
        action: :install,
        server: mcp_server,
        user: current_user,
        context: context_from_referer,
      )

      GitHub.logger.info(
        "MCP server registered",
        "code.namespace": "Copilot::Mcp::ServersController",
        "code.function": "create",
        "gh.actor.id": current_user&.id,
        "gh.request_id": request_id,
      )
      session[:mcp_context] = context_from_referer
      redirect_params = {
        mcp_server_id: mcp_server.id,
        display_name: server_name,
        context: context_from_referer
      }
      redirect_params[:return_url] = params[:return_url] || copilot_immersive_path
      redirect_to mcp_authorization_new_path(redirect_params)
  rescue McpOauth::Errors::UnsupportedServerError,
       McpOauth::Errors::RegistrationEndpointNotFoundError,
       McpOauth::Errors::RegistrationEndpointRedirectError,
       McpOauth::Errors::RegistrationAccessDeniedError,
       McpOauth::Errors::ServerRegistrationError => e
    handle_registration_error(e, server_url)
    end
  end

  def destroy
    config = CopilotMcp::Query.find_mcp_server_config(params[:id].to_i, current_user)
    unless config && config.user_id == current_user.id
      render_404 and return
    end

    begin
      McpOauth::RevokeAndDestroy.call(config: T.must(config), user: current_user)

      if config&.mcp_server
        Hydro::McpServerEventsPublisher.publish_success(
          action: :uninstall,
          server: T.must_because(config.mcp_server) { "Presence is validated to enter this block." },
          user: current_user,
          context: "settings",
        )
      end

      redirect_to mcp_settings_path, notice: "MCP server deleted."
    rescue McpOauth::RevokeAndDestroy::McpServerConfigFailedError => e
      GitHub.logger.error("[ServersController#destroy] Mcp server deletion failed: #{e.class}: #{e.message}")
      redirect_to mcp_settings_path, alert: "An unexpected error occurred, MCP server connection was not removed. Please try again."
    end

  rescue ActiveRecord::RecordNotFound
    render_404
  end

  private

  def handle_registration_error(error, server_url)
    error_map = {
      McpOauth::Errors::UnsupportedServerError            => [:unprocessable_entity, "unsupported_server_type"],
      McpOauth::Errors::RegistrationEndpointNotFoundError => [:not_found,            "registration_endpoint_not_found"],
      McpOauth::Errors::RegistrationEndpointRedirectError => [:unprocessable_entity, "registration_endpoint_redirect"],
      McpOauth::Errors::RegistrationAccessDeniedError     => [:forbidden,            "registration_access_denied"],
      McpOauth::Errors::ServerRegistrationError           => [:bad_request,          "registration_failed"]
    }

    status, code = error_map.fetch(error.class, [:internal_server_error, "unknown_error"])

    # initialize an McpServer instance with just the URL for logging purposes
    server = CopilotMcp::Query.new_server(url: server_url)

    Hydro::McpServerEventsPublisher.publish_error(
      action: :install,
      server: server,
      user: current_user,
      context: context_from_referer,
      error: error
    )

    GitHub.logger.error("MCP client registration failed", "exception.message": error.message, "server_url": server_url)
    render json: { error: code, message: error.message }, status: status
  end

  def current_page
    page = params[:page].to_i
    page.positive? ? page : 1
  end

  def validate_params
    url = params[:mcp_server_url]
    head :bad_request unless url.present? && url.strip.match?(URI::DEFAULT_PARSER.make_regexp)
  end

  def feature_flag_required
    render_404 unless current_user&.feature_flag_enabled?(:copilot_api_dotcom_chat_use_third_party_mcp_servers, default: false)
  end
end
