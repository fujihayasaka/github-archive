# typed: strict
# frozen_string_literal: true

class Repos::DependabotAlerts::AgentAssignmentsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :login_required
  before_action :require_dependabot_alert_assign_to_copilot
  before_action :require_ghas
  before_action :check_dependabot_alerts_write
  before_action :require_copilot_swe_agent_enabled
  before_action :try_parse_json_params, only: [:create]
  before_action :load_alert

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    alert = T.must(@alert)

    assignment_attributes = build_assignment_attributes
    return unless assignment_attributes

    # Verify agent is enabled for the repository
    agent_id = assignment_attributes.agent_id
    if agent_id.to_i.zero?
      # Use default Copilot Coding Agent if none specified
      agent = AgenticApp::CopilotAgent.instance
    else
      agent = AgenticApp.agent_for_integration_id(agent_id)
    end

    unless agent
      render json: { error: "The agent was not found in this repository." }, status: :not_found
      return
    end

    unless agent.enabled_for_repository?(current_repository, current_user)
      render json: { error: "Agent is not enabled for this repository" }, status: :forbidden
      return
    end

    # Supports user selection of a different repository via selection modal
    if current_repository != assignment_attributes.target_repository
      unless agent.enabled_for_repository?(assignment_attributes.target_repository, current_user)
        render json: { error: "Agent is not enabled for the target repository" }, status: :forbidden
        return
      end
    end

    app = agent.integration
    unless app
      render json: { error: "The agent was not found in this repository." }, status: :not_found
      return
    end

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: current_user,
      entry_point: :dependabot_alert_agent_assignments_controller_create,
      user_session: user_session
    )

    begin
      alert.assign_to_copilot(current_user, token, assignment_attributes)
    rescue StandardError => e
      handle_errors(e)
      return
    end

    bot = app.bot
    unless bot
      render json: { error: "Agent not found" }, status: :not_found
      return
    end

    agent_info = {
      id: bot.global_relay_id,
      login: agent.slug,
      name: bot.name,
      avatarUrl: bot.primary_avatar_url(64),
      isAgent: true,
      displayName: agent.display_name,
      profileResourcePath: app&.public_app_path,
    }

    render json: {
      alert_number: alert.number,
      agent: agent_info,
    }, status: :ok
  end

  private

  sig { void }
  def require_dependabot_alert_assign_to_copilot
    return if Dependabot.dependabot_alert_assign_to_copilot_for?(current_repository, current_user)

    render_404
  end

  sig { void }
  def require_ghas
    render_404 unless Dependabot.ghas_available?(current_repository.owner)
  end

  sig { void }
  def check_dependabot_alerts_write
    render_404 unless current_repository.can_resolve_vulnerability_alerts?(current_user)
  end

  sig { void }
  def load_alert
    @alert = T.let(@alert, T.nilable(RepositoryVulnerabilityAlert))
    @alert = current_repository.repository_vulnerability_alerts.find_by(number: params.require(:number))

    unless @alert
      render json: { error: "Alert not found" }, status: :not_found
    end
  end

  sig { void }
  def require_copilot_swe_agent_enabled
    render_404 unless copilot_swe_agent_enabled?
  end

  sig { returns(T::Boolean) }
  def copilot_swe_agent_enabled?
    current_repository.copilot_swe_agent_enabled?(current_user) || false
  end

  sig { returns(T.nilable(Issues::AgentAssignmentNewAttributes)) }
  def build_assignment_attributes
    target_repository = if params[:repo_name_with_owner].present?
      Repositories.domain.by_qualified_name(params[:repo_name_with_owner])
    else
      current_repository
    end
    if target_repository.nil?
      render json: { error: "Repository not found." }, status: :not_found
      return
    end

    # NOTE: Must downcast because IRepository doesn't have visible_and_readable_by? method
    target_repo = T.cast(target_repository, Repository) # rubocop:disable GitHub/AvoidCast
    unless target_repo.writable_by?(current_user)
      render json: { error: "Repository not found." }, status: :not_found
      return
    end

    if target_repo.archived?
      render json: { error: "Cannot assign the agent to issues in archived repositories." }, status: :unprocessable_entity
      return
    end

    # Only allow model parameter if feature flag is enabled
    model = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, current_user, default: false)
      params[:model]
    end

    agent_id = params[:agent_id].present? ? params[:agent_id].to_i : nil

    Issues::AgentAssignmentNewAttributes.new(
      target_repository: target_repository,
      base_ref: params[:base_ref],
      custom_instructions: params[:custom_instructions],
      custom_agent: params[:custom_agent],
      agent_id: agent_id,
      remote_ip: request&.remote_ip,
      model: model,
      skip_pull_request: ActiveModel::Type::Boolean.new.cast(params[:skip_pull_request]),
    )
  end

  # Handles errors raised during agent assignment and renders appropriate JSON error responses.
  sig { params(error: Exception).void }
  def handle_errors(error)
    case error
    when CopilotAPI::NotFoundError
      render json: { error: "The agent was not found in this repository." }, status: :forbidden
    when CopilotAPI::UnauthorizedError
      render json: { error: "Please check that you have permission to assign in the target repository." }, status: :forbidden
    else
      if CopilotSweAgentJobHelper.timeout_error?(error)
        render json: { error: "Failed to assign the agent after multiple retries. Please try again later." }, status: :gateway_timeout
      else
        Failbot.report(error, {
          app: "github",
          feature: "dependabot_alert_copilot_assign",
          context: "dependabot_alerts_agent_assignments_controller"
        })
        render json: {
          error: "Something went wrong while assigning the agent. Please try again later, or contact support if the problem persists.",
        }, status: :internal_server_error
      end
    end
  end
end
