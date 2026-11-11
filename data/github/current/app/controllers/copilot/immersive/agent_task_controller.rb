# typed: true
# frozen_string_literal: true

class Copilot::Immersive::AgentTaskController < Copilot::ImmersiveController
  before_action :check_task_view_enabled, only: [:show]
  before_action :ensure_pull_request_access, only: [:show]

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]
  )

  def show
    respond_to do |format|
      format.html { super }
      format.json { render json: app_payload }
    end
  end

  protected

  # Override to provide dynamic title for agent tasks
  def page_title
    task_title = pull&.title
    task_title ? "#{task_title} · GitHub Copilot" : "Task · GitHub Copilot"
  end

  private

  memoize def agent_tasks_enabled?
    Copilot::Public::User.new(current_user).swe_agent_enabled?
  end

  memoize def steering_enabled?
    Copilot::Public::User.new(current_user).has_copilot_access?
  end

  def check_task_view_enabled
    render_404 unless current_user&.feature_flag_enabled?(:copilot_swe_agent_progress_commands, default: false)
  end

  def ensure_pull_request_access
    if pull.blank?
      render_404
      return
    end

    render_404 unless pull.repository&.readable_by?(current_user)
  end

  def app_payload
    user = T.must(current_user)

    # Prefetch the sessions for the PR
    token = CopilotSessions::CopilotApiToken.get_encrypted(user:, entry_point: :agent_task_controller_show, user_session: user_session)
    sessions = CopilotSessions::AgentSession.for_pull_request(
      user:,
      pull:,
      token:,
      user_session:
    )
    session_id = params[:session_id]
    param_session_missing = sessions.none? { |session| session.id == session_id }

    if (sessions.empty? || param_session_missing) && session_id.present?
      session = CopilotSessions::AgentSession.for_session(
        user:,
        session_id:,
        user_session:,
        token:
      )
      sessions = [session].compact
    end

    # Call the base class method to get the default payload
    super.merge({
      pull: CopilotSessions::Payloads::Pull.new(pull_request: pull, include_body: true).call,
      sessions: sessions.map(&:session),
      currentUser: CopilotSessions::Payloads::PublicUser.new(user).call,
      currentUserCanPush: !!pull.repository&.authorized_to_write?(user),
      agentTasksEnabled: agent_tasks_enabled?, # TODO: Remove once the client is no longer consuming it
      steeringEnabled: steering_enabled?,
      sessionsPollingInterval: CopilotSessions::Public.copilot_sessions_polling_interval_seconds.value * 1000.0,
      logsPollingInterval: CopilotSessions::Public.copilot_logs_polling_interval_seconds.value * 1000.0,
      sessionOwners: CopilotSessions::AgentSession.get_session_owners(sessions),
      agentMentions: CopilotSessions::Helpers.get_agent_mentions_for_sessions(sessions, pull),
    })
  end

  memoize def pull
    return if params[:global_id].blank?
    type, id = Platform::Helpers::NodeIdentification.from_global_id(params[:global_id])
    return if type != "PullRequest" || id.blank?

    PullRequest.find(id)
  rescue Platform::Errors::NotFound => e
    unless mission_control_catch_globalid_not_found_enabled?
      raise e
    end

    # Log the error but do not return a 500
    GitHub.logger.error("Could not find record for global id: #{params[:global_id]}.", e)
    nil
  end

  def resource_for_conditional_access
    super unless current_user&.feature_flag_enabled?(:copilot_mission_control_cap_fix, default: false)
    pull&.repository || super
  end

  def mission_control_catch_globalid_not_found_enabled?
    current_user&.feature_flag_enabled?("mission-control-catch-globalid-not-found", default: false)
  end
end
