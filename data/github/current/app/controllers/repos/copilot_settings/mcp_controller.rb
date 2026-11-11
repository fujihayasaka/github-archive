# typed: true
# frozen_string_literal: true

class Repos::CopilotSettings::McpController < AbstractRepositoryController
  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_admin_access
  before_action :dotcom_required
  before_action :parse_json_params, only: [:update]
  before_action :has_access_to_mcp_settings

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  def self.react_bundle_name
    "copilot-swe-agent-settings"
  end

  def index
    return render_404 unless mcp_standalone_page_enabled?

    config = Copilot::SweAgentConfiguration.find_by(resource: current_repository)

    render_react_app(
      payload: {
        mcpConfiguration: config&.mcp_configuration,
        endpoint: repo_repo_settings_copilot_mcp_path(current_repository.owner, current_repository.name),
      },
      title: "MCP servers",
      page_data: {
        selected_link: :repo_settings_copilot_mcp
      },
      layout: "layouts/repository/edit_repositories",
    )
  end

  def update
    return render_404 unless mcp_standalone_page_enabled?

    begin
      ::JSON::Validator.validate!(Repos::CopilotSettings::McpSchema::MCPPayload::EXPECTED_MCP_CONFIGURATION_SCHEMA, params["mcp_configuration"], json: true)
    rescue ::JSON::Schema::JsonParseError, ::JSON::Schema::ValidationError => e
      Rails.logger.error("Invalid MCP configuration JSON: #{e.message}, repo: #{current_repository.name_with_display_owner}, repo_id: #{current_repository.id}, actor_id: #{current_user.id}")
      render json: { message: "Invalid MCP configuration JSON. \n #{e.message}" }, status: :unprocessable_entity and return
    end

    config = Copilot::SweAgentConfiguration.find_or_initialize_by(
      resource: current_repository
    )

    config.mcp_configuration = params["mcp_configuration"]
    config.updated_by = current_user

    if config.save
      render json: {
        message: "MCP configuration saved successfully",
        lastEdited: {
          login: current_user.display_login,
          updated_at: config.updated_at
        }
      }
      Copilot::Instrumenter.instrument_swe_agent_mcp_config_updated(
        repo: current_repository,
        actor: current_user,
        new_config: config.mcp_configuration,
      )
    else
      render json: { message: config.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def has_access_to_mcp_settings
    render_404 unless mcp_settings_accessible?
  end

  sig { returns(T::Boolean) }
  def mcp_standalone_page_enabled?
    FeatureFlag.vexi.enabled?("ccr_mcp_repo_settings", [current_repository, current_repository.owner], default: false) ||
      current_repository.feature_enabled_for_repo_or_owner?("copilot-code-reviews-enable-mcp-proxy") ||
      preview_mcp_skills_enabled?
  end

  sig { returns(T::Boolean) }
  def preview_mcp_skills_enabled?
    return false unless FeatureFlag.vexi.enabled?("ccr-enable-preview-mcp-skills", [current_repository, current_repository.owner], default: false)

    if current_repository.in_organization?
      org = current_repository.organization
      return false unless org

      copilot_org = ::Copilot::Organization.new(org)
      copilot_org.code_review_beta_features_enabled?
    else
      copilot_user = current_copilot_user_v2
      return false unless copilot_user

      copilot_user.code_review_beta_features_enabled?
    end
  end

  sig { returns(T::Boolean) }
  def mcp_settings_accessible?
    copilot_swe_agent_enabled? || code_review_enabled?
  end

  sig { returns(T::Boolean) }
  def copilot_swe_agent_enabled?
    current_repository.owner.copilot_swe_agent_enabled_for?(current_repository)
  end

  sig { returns(T::Boolean) }
  def code_review_enabled?
    if current_repository.in_organization?
      org = current_repository.organization
      return false unless org

      copilot_org = ::Copilot::Organization.new(org)
      ::Copilot::Policies::CodeReview.enabled?(copilot_org)
    else
      copilot_user = current_copilot_user_v2
      return false unless copilot_user

      copilot_user.code_review_enabled?
    end
  end
end
