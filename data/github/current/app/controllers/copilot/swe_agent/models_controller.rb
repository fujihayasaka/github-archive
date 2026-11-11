# typed: true
# frozen_string_literal: true

class Copilot::SweAgent::ModelsController < ApplicationController
  include RepositoryControllerMethods

  SWE_AGENT_MODEL_PREFIX = "sweagent-capi:"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    only: [:index]

  before_action :login_required
  before_action :require_copilot_swe_agent_enabled

  def index
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: current_user,
      entry_point: :swe_agent_models_controller,
      user_session: user_session
    )
    staging_env = CopilotSweAgent::SweAgentPath.resolve_env(user: current_user, repository: current_repository)
    models = CopilotSweAgent::CodingAgentModel.for_user(
      user: current_user,
      token: token,
      staging_env:,
      vendor: params[:vendor],
    )

    current_model = fetch_current_session_model(token, models) if params[:pull_id].present?

    respond_to do |format|
      format.json do
        response_data = { models: models.map(&:to_h) }
        response_data[:current_model] = current_model if current_model.present?
        render json: response_data
      end
    end
  end

  private

  def fetch_current_session_model(token, available_models)
    pull = current_repository.pull_requests.find_by(id: params[:pull_id])
    return nil unless pull

    sessions = CopilotSessions::AgentSession.for_pull_request(
      user: current_user,
      pull: pull,
      token: token,
      user_session: user_session
    )

    most_recent_session = sessions.select { |s| s.created_at.present? }.max_by(&:created_at)
    model = most_recent_session&.model
    # Strip the sweagent-capi: prefix — the picker uses bare model IDs
    model = model&.delete_prefix(SWE_AGENT_MODEL_PREFIX)

    # Only return the model if the user has access to it. The initial CCA task
    # may have used a model via auto-mode fallback that bypasses policy checks,
    # but returning it here would cause the frontend to append it as an explicit
    # model request on subsequent @copilot comments, which fails policy validation.
    return nil unless model && available_models.any? { |m| m.id == model }
    model
  rescue StandardError => e
    GitHub.logger.error("Failed to fetch current session model", {
      "code.function": "fetch_current_session_model",
      "code.namespace": self.class.name,
      "error.message": e.message,
      "error.class": e.class.name,
    })
    nil
  end

  def require_copilot_swe_agent_enabled
    unless current_repository &&
           current_repository.copilot_swe_agent_enabled?(current_user) &&
           FeatureFlag.vexi.enabled?(:coding_agent_model_selection, current_user, default: false) &&
           FeatureFlag.vexi.enabled?(:copilot_swe_agent_pr_comment_model_picker, current_user, default: false)
      render_404
    end
  end

  def resource_for_conditional_access
    current_repository
  end
end
