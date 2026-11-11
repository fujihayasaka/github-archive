# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include MissionControlExperimentEvents

  before_action :load_current_pull_request, except: [:create]
  before_action :login_required
  before_action :require_copilot_swe_agent_enabled
  before_action :redirect_to_mission_control, only: [:show]

  allow_verified_fetch only: [:create]

  attr_reader :pull

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [:create].freeze

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

  def create
    emit_experiment_exposure(
      surface_type: :AGENT_SURFACE_TYPE_MISSION_CONTROL,
      entry_point: "agent_session_create",
    )

    token = CopilotSessions::CopilotApiToken.get_encrypted(user: current_user, entry_point: :agent_sessions_controller_create, user_session: user_session)

    # Get the Copilot API client
    copilot_api = Copilot::User.copilot_api(
      user: current_user,
      integration_id: CopilotAPI::COPILOT_SWE_AGENT,
      token:,
    )

    # If a workflow_run_id is provided, use its branch as the base_ref
    workflow_run_branch = find_workflow_run(params[:workflow_run_id])&.head_branch

    # Create the agent session via CAPI
    response = copilot_api.create_swe_agent_job(
      nwo: current_repository.name_with_display_owner,
      problem_statement: params[:problem_statement],
      base_ref: params[:base_ref] || workflow_run_branch || current_repository.default_branch,
      event_type: params[:event_type] || "",
      creation_id: params[:creation_id] || "",
      custom_agent: params[:custom_agent],
      agent_id: params[:agent_id]&.to_i,
      event_url: params[:event_url] || "",
      event_content: params[:event_content],
      model: params[:model_id] || "",
    )

    session_id = response["session_id"]

    # Redirect to the global copilot agents page
    redirect_to copilot_agent_tasks_show_path
  rescue CopilotAPI::Error => e
    flash[:error] = "Failed to create agent session: #{e.message}"
    redirect_back(fallback_location: repository_path(current_repository))
  rescue StandardError => e
    Rails.logger.error("Failed to create agent session: #{e.message}")
    flash[:error] = "Failed to create agent session"
    redirect_back(fallback_location: repository_path(current_repository))
  end

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
    session_id = params[:session_id]
    redirect_to copilot_agent_task_url(global_id: @pull.global_relay_id, session_id: session_id)
  end
end
