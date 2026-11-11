# typed: true
# frozen_string_literal: true

class Repos::Agents::AgentSessionsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include MissionControlExperimentEvents

  before_action :load_current_pull_request, except: [:create]
  before_action :login_required
  before_action :require_copilot_swe_agent_enabled, only: [:create]
  before_action :require_copilot_agent_or_ccr_access, only: [:show]
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

    # If a check_run_id is provided, find its workflow run and use its branch as the base_ref
    # Also accept workflow_run_id for backward compatibility during deploy
    workflow_run = find_workflow_run_from_check_run(params[:check_run_id] || params[:workflow_run_id])
    existing_pr_head_ref = workflow_run&.head_branch
    base_ref = existing_pr_head_ref || params[:base_ref] || current_repository.default_branch

    request_params = {
      actor_id: current_user.id,
      repo_id: current_repository.id,
      owner_id: current_repository.owner_id,
      problem_statement: params[:problem_statement].to_s,
      custom_agent: params[:custom_agent].to_s,
      agent_id: params[:agent_id]&.to_i || 0,
      event_type: params[:event_type] || "",
      event_url: params[:event_url] || "",
      event_identifiers: [params[:creation_id] || ""],
      event_content: params[:event_content].to_s,
      model: params[:model_id] || "",
      features: Sweagentd::JobsAPI::V1::Features.new(
        pull_request: Sweagentd::JobsAPI::V1::PullRequestFeature.new(
          base_ref: base_ref,
        ),
      ),
    }

    if base_ref != current_repository.default_branch
      request_params[:features].pull_request.head_ref = base_ref
      request_params[:features].pull_request.base_ref =
        if workflow_run&.trigger.is_a?(PullRequest)
          workflow_run.trigger.base_ref
        else
          ""
        end
    end

    create_job_request = Sweagentd::JobsAPI::V1::CreateJobRequest.new(request_params)

    response = GitHub::Sweagentd::Client.jobs.create_job(create_job_request, remote_ip: request.remote_ip)
    session_id = response.data&.session_id
    raise GitHub::Sweagentd::Client::Jobs::Error, "No session_id returned" if session_id.blank?

    # Redirect to the started session
    redirect_to repo_session_path(
      user_id: current_repository.owner_display_login,
      repository: current_repository.name,
      session_id: session_id,
    )
  rescue GitHub::Sweagentd::Client::Jobs::Error => e
    flash[:error] = "Failed to create agent session: #{e.message}"
    redirect_back(fallback_location: repository_path(current_repository))
  rescue StandardError => e
    Rails.logger.error("Failed to create agent session: #{e.message}")
    flash[:error] = "Failed to create agent session"
    redirect_back(fallback_location: repository_path(current_repository))
  end

  def show
    session_id = params[:session_id]
    if session_id.present? && session_id !~ /\A[a-zA-Z0-9\-_]+\z/
      render_404
      return
    end
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
  def find_workflow_run_from_check_run(check_run_id)
    return nil unless check_run_id
    check_run = CheckRun.find_by(id: check_run_id, repository_id: current_repository.id)
    check_run&.check_suite&.workflow_run
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

  def require_copilot_agent_or_ccr_access
    copilot_user = Copilot::Public::User.for(current_user)
    render_404 unless current_repository.copilot_swe_agent_enabled?(current_user) || copilot_user.code_review_enabled?
  end

  def redirect_to_mission_control
    session_id = params[:session_id]
    redirect_to copilot_agent_task_url(global_id: @pull.global_relay_id, session_id: session_id)
  end
end
