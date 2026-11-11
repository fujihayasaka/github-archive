# typed: true
# frozen_string_literal: true

class Copilot::Immersive::AgentTaskController < Copilot::ImmersiveController
  include MissionControlExperimentEvents

  before_action :ensure_pull_request_access, only: [:show]
  before_action :redirect_to_repo_agent_task_view, only: [:show]

  depends_on_clusters(
    ApplicationRecord::Ballast,
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
    if agent_tasks_enabled?
      emit_experiment_exposure(
        surface_type: :AGENT_SURFACE_TYPE_IMMERSIVE,
        entry_point: "immersive_agent_task",
        session_id: params[:session_id],
      )
    end

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

  def ensure_pull_request_access
    if pull.blank?
      render_404
      return
    end

    render_404 unless pull.repository&.readable_by?(current_user)
  end

  def redirect_to_repo_agent_task_view
    return unless current_user&.feature_flag_enabled?(:copilot_mission_control_link_to_sessions_in_repo, default: false) && !current_user&.feature_flag_enabled?(:copilot_mission_control_link_to_hyperspace, default: false)

    redirect_to repo_agents_task_path(pull.repository.owner, pull.repository.name, pull.number, session_id: params[:session_id]), status: :moved_permanently
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
    payload = super.merge({
      pull: CopilotSessions::Payloads::Pull.new(pull_request: pull, include_body: true, include_diff: true).call,
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

    # Include the SSR-generated auth token so the client can store it
    # This avoids the client needing to fetch a new token on page load
    payload[:initialAuthToken] = {
      token: token.value,
      expiration: token.expiration&.iso8601,
      ssoOrgIDs: saml_for_user.protected_organization_ids.map(&:to_s)
    }

    payload
  end

  memoize def pull
    return if params[:global_id].blank?
    type, id = Platform::Helpers::NodeIdentification.from_global_id(params[:global_id])
    return if type != "PullRequest" || id.blank?

    PullRequest.find(id)
  rescue Platform::Errors::NotFound => e
    # Log the error but do not return a 500
    GitHub.logger.error("Could not find record for global id: #{params[:global_id]}.", e)
    nil
  end

  def resource_for_conditional_access
    pull&.repository || super
  end
end
