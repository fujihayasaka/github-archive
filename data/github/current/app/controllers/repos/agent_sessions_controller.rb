# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsController < AbstractRepositoryController
  include ApplicationController::JsonDependency

  before_action :load_current_pull_request
  before_action :login_required
  before_action :require_copilot_swe_agent_enabled

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
  only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    last_session = CopilotSweAgent::AgentSession.for_pull_request(
      user: current_user,
      pull: pull,
      user_session: user_session
    ).last

    unless last_session.present?
      # Not an error case, don't raise.
      render_404
      return
    end

    redirect_to repo_agent_session_path(session_id: last_session.session["id"])
  end

  def show
    add_client_feature_flag([
      :logs_pr_tag_strip,
      :copilot_coding_agent_premium_requests,
    ])
    # Reuse the token across both requests here
    token = CopilotSweAgent::CopilotApiToken.get_encrypted(user: current_user, entry_point: :agent_sessions_controller_show, user_session: user_session)
    sessions_data = CopilotSweAgent::AgentSession.for_pull_request(
      user: current_user,
      pull:,
      token:,
      user_session:
    )

    logs_data = current_user.copilot_api(integration_id: CopilotAPI::COPILOT_SWE_AGENT, token:).get_swe_agent_logs(session_id: params[:session_id])
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
          showCopilotCodingAgentPremiumRequestsBanner: CopilotSweAgent::Public.show_copilot_coding_agent_premium_requests_banner(current_user),
          currentUser: Repos::ReactPayload.current_user_payload(current_user)
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
    logs_polling_interval = (CopilotSweAgent::Public.copilot_logs_polling_interval_seconds.value * 1000.0)
    sessions_polling_interval = (CopilotSweAgent::Public.copilot_sessions_polling_interval_seconds.value * 1000.0)

    {
      logsPollingInterval: logs_polling_interval,
      sessionsPollingInterval: sessions_polling_interval,
    }
  end

  def json_bad_request(message)
    render json: { message: }, status: :bad_request
  end

  def find_session(session_id)
    sessions = CopilotSweAgent::AgentSession.for_pull_request(
      user: current_user,
      pull: pull,
      user_session: user_session
    )

    sessions.map(&:session).find { |s| s["id"] == session_id }
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
end
