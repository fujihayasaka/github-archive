# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsController < AbstractRepositoryController
  include ApplicationController::JsonDependency

  before_action :load_current_pull_request
  before_action :login_required
  before_action :require_copilot_swe_agent_enabled
  before_action :redirect_to_mission_control

  attr_reader :pull

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [].freeze

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::IamAbilities,
  only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    add_client_feature_flag([
      :logs_pr_tag_strip,
    ])
    session_id = params[:session_id]
    # Reuse the token across both requests here
    token = CopilotSessions::CopilotApiToken.get_encrypted(user: current_user, entry_point: :agent_sessions_controller_show, user_session: user_session)
    sessions_data = CopilotSessions::AgentSession.for_pull_request(
      user: current_user,
      pull:,
      token:,
      user_session:
    )

    param_session_missing = sessions_data.none? { |session| session.id == session_id }

    if (sessions_data.empty? || param_session_missing) && session_id.present?
      session = CopilotSessions::AgentSession.for_session(
        user: current_user,
        session_id:,
        user_session:,
        token:
      )
      sessions = [session].compact
    end


    logs_data = Copilot::User.copilot_api(user: current_user, integration_id: CopilotAPI::COPILOT_SWE_AGENT, token: token).get_swe_agent_logs(session_id: params[:session_id])
    # Show the app with a focused session
    render_react_html(
      title: "Sessions · #{pull.title}",
      payload: {
        sessionRoute: {
          pull: pull_data,
          repository: repo_data,
          sessions: sessions_data.map(&:session),
          logs: logs_data["results"],
          activeSessionId: params[:session_id],
          pollingIntervals: polling_intervals,
          showCopilotCodingAgentPremiumRequestsBanner: CopilotSessions::Public.show_copilot_coding_agent_premium_requests_banner(current_user),
          currentUser: Repos::ReactPayload.current_user_payload(current_user),
          sessionOwners: CopilotSessions::AgentSession.get_session_owners(sessions_data),
        },
      },
    )
  end

  private

  def repo_data
    Repos::ReactPayload.current_repository_payload(
      current_repository,
      current_user_can_push: current_user_can_push?
    )
  end

  def pull_data
    { id: pull.id, number: pull.number, state: pull.state, title: pull.title, reviewable_state: pull.reviewable_state }
  end

  # The dials are set in seconds, but we need to transform them to milliseconds for the client
  def polling_intervals
    logs_polling_interval = (CopilotSessions::Public.copilot_logs_polling_interval_seconds.value * 1000.0)
    sessions_polling_interval = (CopilotSessions::Public.copilot_sessions_polling_interval_seconds.value * 1000.0)

    {
      logsPollingInterval: logs_polling_interval,
      sessionsPollingInterval: sessions_polling_interval,
    }
  end

  def json_bad_request(message)
    render json: { message: }, status: :bad_request
  end

  # These are basically copied from WorkflowRunsController but will be removed after Build once we implement a more
  # elegant way to terminate a running session.
  def find_workflow_run(workflow_run_id)
    return nil unless workflow_run_id
    workflow_run = Actions::WorkflowRun.find_by(id: workflow_run_id)
    if !workflow_run || is_missing_check_suite(workflow_run) || workflow_run.check_suite&.repository_id != current_repository.id
      return nil
    end
    workflow_run
  end

  def is_missing_check_suite(workflow_run)
    if workflow_run.check_suite.nil?
      true
    end
  end
  # End copied WorkflowRunsController code

  def load_current_pull_request
    begin
      @pull = PullRequests::PullRequestAccessor.new.by_number(repository_id: current_repository.id, number: params[:pull_number].to_i)
    rescue GH::Errors::ObjectNotFound
      render_404
    end
  end

  def require_copilot_swe_agent_enabled
    render_404 unless current_repository.copilot_swe_agent_enabled?(current_user)
  end

  def redirect_to_mission_control
    # Only redirect if the MC flag is enabled AND the logs page override flag is disabled to allow us to continue to develop there if needed
    if FeatureFlag.vexi.enabled?(:copilot_swe_agent_progress_commands, current_user, default: false) && !FeatureFlag.vexi.enabled?(:copilot_session_logs_page_override, current_user, default: false)
      session_id = params[:session_id]
      redirect_to copilot_agent_task_url(global_id: @pull.global_relay_id, session_id: session_id)
    end
  end
end
