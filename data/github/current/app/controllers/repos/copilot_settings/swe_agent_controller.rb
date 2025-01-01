# typed: true
# frozen_string_literal: true

class Repos::CopilotSettings::SweAgentController < AbstractRepositoryController
  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_admin_access
  before_action :dotcom_required
  before_action :parse_json_params, only: [:update]
  before_action :has_access_to_swe_agent

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:index]

  def self.react_bundle_name
    "copilot-swe-agent-settings"
  end

  EXPECTED_MCP_CONFIGURATION_SCHEMA = {
    "properties": {
    "mcpServers": {
      "type": "object",
      "patternProperties": {
        "^[a-zA-Z0-9_-]+$": {
          "type": "object",
          "properties": {
            "command": { "type": "string" },
            "type": { "type": "string" },
            "args": {
              "type": "array",
              "items": { "type": "string" }
            },
            "tools": {
              "type": "array",
              "items": { "type": "string" },
              "optional": false
            },
            "env": {
              "type": "object",
              "additionalProperties": { "type": "string" },
              "optional": true
            }
          },
          "required": %w[command args tools],
          "additionalProperties": false
        }
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": false
  }.freeze


  def index
    config = Copilot::SweAgentConfiguration.find_by(resource: current_repository)
    render_react_app(
      payload: {
        mcpConfiguration: config&.mcp_configuration,
        endpoint: repo_repo_settings_copilot_swe_agent_path(owner.display_login, current_repository.name),
        access_warning_banner_content: access_warning_banner_content,
      },
      title: Copilot::COPILOT_SWE_AGENT,
      page_data: {
        selected_link: :repo_settings_copilot_swe_agent
      },
      layout: "layouts/repository/edit_repositories",
    )
  end

  def update
    begin
      ::JSON::Validator.validate!(Repos::CopilotSettings::McpSchema::MCPPayload::EXPECTED_MCP_CONFIGURATION_SCHEMA, params["mcp_configuration"], json: true)
    rescue ::JSON::Schema::JsonParseError, ::JSON::Schema::ValidationError => e
      Rails.logger.error("Invalid MCP configuration JSON: #{e.message}, submitted parameters: #{params["mcp_configuration"]}")
      render json: { message: "Invalid MCP configuration JSON. \n #{e.message}" }, status: :unprocessable_entity and return
    end

    config = Copilot::SweAgentConfiguration.find_or_initialize_by(
      resource: current_repository
    )

    config.mcp_configuration = params["mcp_configuration"]
    config.updated_by = current_user

    if config.save
      render json: {
        message: "Configuration saved successfully",
        lastEdited: {
          login: current_user.display_login,
          updated_at: config.updated_at
        }
      }
    else
      render json: { message: config.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def has_access_to_swe_agent # rubocop:todo GitHub/UseRestfulActions
    render_404 unless current_repository.owner.copilot_swe_agent_enabled_for?(current_repository)
  end

  sig { returns(T.nilable(String)) }
  def access_warning_banner_content # rubocop:todo GitHub/UseRestfulActions
    public_user = Copilot::Public::User.new(current_user)

    if !public_user.has_copilot_access? || !public_user.has_premium_access?
      return "You can configure Copilot coding agent for other users with access to this repository, but you won't be able to assign tasks to Copilot because you don't have a Copilot Pro+ or Copilot Enterprise license."
    elsif !public_user.swe_agent_enabled?
      return "You can configure Copilot coding agent for other users with access to this repository, but you won't be able to assign tasks to Copilot because the Copilot coding agent policy has been disabled by an administrator."
    end

    nil
  end
end
