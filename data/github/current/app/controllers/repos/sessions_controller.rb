# typed: strict
# frozen_string_literal: true

class Repos::SessionsController < AbstractRepositoryController
  before_action :login_required
  before_action :require_copilot_mission_control_sessions_redirect_enabled
  before_action :require_copilot_swe_agent_enabled

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([].freeze, T::Array[T.untyped])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  # GET /:owner/:repo/sessions/:session_id
  sig { void }
  def show
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: current_user,
      entry_point: :sessions_controller_show,
      user_session: user_session,
    )

    session = CopilotSessions::AgentSession.for_session(
      user: current_user,
      session_id: params[:session_id],
      token: token,
      user_session: user_session,
    )

    if session.nil? || session.task_id.blank?
      render_404
      return
    end

    redirect_to repo_task_path(
      user_id: current_repository.owner_display_login,
      repository: current_repository.name,
      task_id: session.task_id,
      session_id: params[:session_id],
    )
  end

  private

  sig { void }
  def require_copilot_mission_control_sessions_redirect_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:copilot_mission_control_sessions_redirect, current_user, default: false)
  end

  sig { void }
  def require_copilot_swe_agent_enabled
    render_404 unless current_repository.copilot_swe_agent_enabled?(current_user)
  end
end
