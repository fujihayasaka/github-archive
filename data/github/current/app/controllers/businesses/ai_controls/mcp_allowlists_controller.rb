# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_allowlist_client"

class Businesses::AiControls::McpAllowlistsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::AiControls::McpAllowlistsController#create",
    "Businesses::AiControls::McpAllowlistsController#update",
    "Businesses::AiControls::McpAllowlistsController#destroy",
  ].freeze

  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  layout "layouts/react_business"

  allow_verified_fetch only: [:index]

  before_action :ensure_not_standalone_copilot_business
  before_action :require_ai_controls_enabled
  before_action :ai_controls_read_required
  before_action :ensure_allowlist_feature_flag_enabled
  before_action :ai_controls_write_required, only: [:create, :update, :destroy]

  sig { void }
  def index
    allowlists = fetch_allowlists
    assignments = fetch_assignments

    render "businesses/ai_controls/mcp/allowlists", locals: {
      business: this_business,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      is_admin: this_business&.adminable_by?(current_user) || false,
      title: "MCP Allowlists",
      allowlists: allowlists,
      assignments: assignments,
    }
  end

  sig { void }
  def create
    name = params.dig(:allowlist, :name).to_s.strip
    description = params.dig(:allowlist, :description).to_s.strip.presence

    if name.blank?
      flash[:error] = "Allowlist name is required."
      redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
      return
    end

    enterprise_id = this_business.id.to_s
    McpRegistry::EnterpriseAllowlistClient.create_allowlist(
      enterprise_id: enterprise_id,
      name: name,
      description: description,
      token: mcp_registry_token,
    )

    flash[:success] = "Your new MCP allowlist has been successfully created."
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    flash[:error] = error_message_for(e)
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  rescue StandardError => e
    Rails.logger.error("MCP Registry create failed: #{e.class}: #{e.message}")
    flash[:error] = "Something went wrong. Please try again."
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  end

  sig { void }
  def update
    allowlist_id = params[:id].to_s
    name = params.dig(:allowlist, :name).to_s.strip.presence
    description = params.dig(:allowlist, :description).to_s.strip

    enterprise_id = this_business.id.to_s
    McpRegistry::EnterpriseAllowlistClient.update_allowlist(
      enterprise_id: enterprise_id,
      allowlist_id: allowlist_id,
      name: name,
      description: description,
      token: mcp_registry_token,
    )

    flash[:success] = "Allowlist updated successfully."
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    flash[:error] = error_message_for(e)
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  rescue StandardError => e
    Rails.logger.error("MCP Registry update failed: #{e.class}: #{e.message}")
    flash[:error] = "Something went wrong. Please try again."
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  end

  sig { void }
  def destroy
    allowlist_id = params[:id].to_s

    enterprise_id = this_business.id.to_s
    McpRegistry::EnterpriseAllowlistClient.delete_allowlist(
      enterprise_id: enterprise_id,
      allowlist_id: allowlist_id,
      token: mcp_registry_token,
    )

    flash[:success] = "Allowlist deleted successfully."
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    flash[:error] = error_message_for(e)
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  rescue StandardError => e
    Rails.logger.error("MCP Registry delete failed: #{e.class}: #{e.message}")
    flash[:error] = "Something went wrong. Please try again."
    redirect_to mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  end

  private

  sig { override.returns(String) }
  def ai_controls_section_title
    "MCP Allowlists"
  end

  sig { override.returns(Symbol) }
  def ai_controls_selected_link
    :businesses_ai_controls_mcp
  end

  sig { void }
  def require_ai_controls_enabled
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def ensure_allowlist_feature_flag_enabled
    unless current_user&.feature_flag_enabled?(:copilot_mcp_registry_enterprise_allowlist_ui, default: false)
      render_404
    end
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def fetch_allowlists
    enterprise_id = this_business.id.to_s
    token = mcp_registry_token
    result = McpRegistry::EnterpriseAllowlistClient.list_allowlists(enterprise_id: enterprise_id, token: token)
    allowlists = result["allowlists"] || result.fetch("items", [])
    enrich_allowlists(allowlists)
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    flash.now[:error] ||= if Rails.env.development?
      "Unable to load allowlists: #{e.status} - #{e.body.inspect}"
    else
      "Unable to load allowlists. The MCP Registry service may be unavailable."
    end
    []
  rescue StandardError => e
    Rails.logger.error("[MCP AllowlistsController] Error fetching allowlists: #{e.class}: #{e.message}")
    flash.now[:error] ||= if Rails.env.development?
      "Unable to load allowlists: #{e.class}: #{e.message}"
    else
      "Unable to load allowlists. The MCP Registry service may be unavailable."
    end
    []
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def fetch_assignments
    enterprise_id = this_business.id.to_s
    token = mcp_registry_token
    result = McpRegistry::EnterpriseAllowlistClient.list_assignments(enterprise_id: enterprise_id, token: token)
    result["assignments"] || result.fetch("items", [])
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    []
  rescue StandardError => e
    Rails.logger.error("[MCP AllowlistsController] Error fetching assignments: #{e.class}: #{e.message}")
    []
  end

  sig { params(error: McpRegistry::EnterpriseAllowlistClient::ApiError).returns(String) }
  def error_message_for(error)
    case error.status
    when 409
      "An allowlist with that name already exists."
    when 422
      "Validation failed. Please check your input and try again."
    when 403
      "You don't have permission to perform this action."
    when 404
      "The requested allowlist could not be found."
    else
      "Something went wrong. Please try again."
    end
  end

  MCP_REGISTRY_TOKEN_SCOPE = "mcp_registry"

  sig { returns(String) }
  def mcp_registry_token
    current_user.signed_auth_token(
      scope: MCP_REGISTRY_TOKEN_SCOPE,
      expires: 5.minutes.from_now,
    )
  end

  # Enriches allowlist entries by resolving user IDs in created_by/updated_by
  # to hashes with login and avatar_url, which the view expects.
  sig { params(allowlists: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def enrich_allowlists(allowlists)
    user_ids = allowlists.flat_map { |a| [a["created_by"], a["updated_by"]] }.compact.grep(Integer).uniq
    return allowlists if user_ids.empty?

    users_by_id = User.where(id: user_ids).index_by(&:id)

    allowlists.each do |allowlist|
      %w[created_by updated_by].each do |field|
        val = allowlist[field]
        next unless val.is_a?(Integer)

        user = users_by_id[val]
        allowlist[field] = if user
          { "login" => user.display_login, "avatar_url" => user.primary_avatar_url }
        else
          { "login" => "user-#{val}", "avatar_url" => nil }
        end
      end
    end

    allowlists
  end
end
