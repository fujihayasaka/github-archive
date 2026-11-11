# typed: strict
# frozen_string_literal: true

class Repos::DependabotAlerts::AgentAssignmentsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  CONTROLLER_STATUS_MAP = T.let({
    agent_not_found: :not_found,
    agent_not_assignable: :unprocessable_entity,
    agent_not_enabled: :forbidden,
    target_repo_not_found: :not_found,
    target_repo_archived: :unprocessable_entity,
    copilot_forbidden: :forbidden,
    copilot_timeout: :gateway_timeout,
    copilot_unexpected: :internal_server_error,
  }.freeze, T::Hash[Symbol, Symbol])

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

    service = Dependabot::AgentAssignmentService.new

    agent, bot, app = nil, nil, nil
    begin
      agent, bot, app = service.resolve_agent!(
        agent_id: assignment_attributes.agent_id,
        repo: current_repository,
        user: current_user,
      )
    rescue Dependabot::AgentAssignmentService::Error => e
      render json: { error: e.message }, status: CONTROLLER_STATUS_MAP.fetch(e.error_kind)
      return
    end

    # Supports user selection of a different repository via selection modal
    begin
      service.validate_target_repo!(
        target_repo: assignment_attributes.target_repository,
        source_repo: current_repository,
        agent: agent,
        user: current_user,
      )
    rescue Dependabot::AgentAssignmentService::Error => e
      render json: { error: e.message }, status: CONTROLLER_STATUS_MAP.fetch(e.error_kind)
      return
    end

    # Persist the assignee before firing the CAPI job, matching the pattern used in Issues.
    begin
      alert.update_assignees(alert.assignees.to_a | [bot], current_user)
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
      return
    end

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: current_user,
      entry_point: :dependabot_alert_agent_assignments_controller_create,
      user_session: user_session
    )

    begin
      service.execute_assignment!(
        alert: alert,
        user: current_user,
        token: token,
        attributes: assignment_attributes,
        failbot_context: "dependabot_alerts_agent_assignments_controller",
      )
    rescue Dependabot::AgentAssignmentService::Error => e
      render json: { error: e.message }, status: CONTROLLER_STATUS_MAP.fetch(e.error_kind)
      return
    end

    agent_info = {
      id: bot.global_relay_id,
      login: agent.slug,
      name: bot.name,
      avatarUrl: bot.primary_avatar_url(64),
      isAgent: true,
      displayName: agent.display_name,
      profileResourcePath: app.public_app_path,
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
end
