# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsController < Repos::AgentSessionsBaseController
  include ApplicationController::VerifiedFetchDependency

  before_action :require_xhr_request, only: [:destroy]

  allow_verified_fetch only: [:destroy]

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

    if request.xhr?
      render(
        Issues::References::CopilotSweAgentComponent.new(
          pull: pull,
          current_user_can_push: current_user_can_push?,
          active_session: last_session.session
        ),
        layout: false
      )
    else
      redirect_to repo_agent_session_path(session_id: last_session.session["id"])
    end
  end

  def show
    add_client_feature_flag([:logs_pr_tag_strip, :copilot_coding_agent_premium_requests, :copilot_coding_agent_fix_oswe])
    # Reuse the token across both requests here
    token = CopilotSweAgent::AgentSession.mint_token(user: current_user, entry_point: :agent_sessions_controller_show, user_session: user_session).first
    sessions_data = CopilotSweAgent::AgentSession.for_pull_request(
      user: current_user,
      pull:,
      token:,
      user_session:
    )

    logs_data = if GitHub.copilot_swe_agent_mock_session_data
      JSON.parse(File.read("ui/packages/agent-sessions/mocks/session_logs_response.json"))
    else
      current_user.copilot_api(integration_id: CopilotAPI::COPILOT_SWE_AGENT, token:).get_swe_agent_logs(session_id: params[:session_id])
    end
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
          useMockData: GitHub.copilot_swe_agent_mock_session_data,
          pollingIntervals: polling_intervals,
        },
      },
    )
  end

  def destroy
    return render_404 unless current_user_can_push?
    return render_404 unless session = find_session(params[:session_id])

    return json_bad_request("session state (#{session['state']}) cannot be stopped") unless session["state"] == "in_progress"

    # For dev mode we just pretend this worked since we are using mock data and don't actually have a workflow run
    # to delete.
    return head :ok if GitHub.copilot_swe_agent_mock_session_data

    workflow_run = find_workflow_run(session["workflow_run_id"])
    return render_404 unless workflow_run

    check_suite = workflow_run.check_suite

    return json_bad_request("check suite status (#{check_suite.status}) cannot be cancelled") unless check_suite.cancelable?

    check_suite.cancel(actor: current_user)

    head :ok
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

  def require_xhr_request
    render_404 unless request.xhr?
  end
end
