# typed: true
# frozen_string_literal: true

# Handles the /agents/pull/:pull_number route — the pull-number-based entry
# point to a task view.
#
# JSON requests return the task payload (consumed by useTaskPayload in the
# frontend). HTML requests redirect to the canonical /tasks/:task_id URL
# when the feature flag is enabled.
class Repos::Agents::PullTasksController < AbstractRepositoryController
  include Repos::Agents::Common
  include MissionControlExperimentEvents

  before_action :load_pull_request

  attr_reader :pull

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [].freeze

  depends_on_clusters ApplicationRecord::Authnd,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  PAGE_DATA_TASK = {
    hide_footer: true,
    selected_link: :repo_agents_task,
  }.freeze

  # GET /:owner/:repo/agents/pull/:pull_number
  def show
    user = T.must(current_user)
    token = CopilotSessions::CopilotApiToken.get_encrypted(user:, entry_point: :agents_controller_task, user_session: user_session)

    sessions = fetch_sessions_for_pull(user:, pull:, token:)

    # Decoupled-PR fallback: when the session's resource fields were never
    # populated, search the user's recent tasks for one linked to this PR.
    if pull && sessions.empty? && @task.blank? &&
        user.feature_flag_enabled?(:coding_agent_logs_in_pr, default: false)
      @task = find_task_for_pull_request(user:, pull:, token:)
      sessions = @task&.sessions || []
    end

    # Short-circuit: when redirect is enabled, resolve task_id and redirect
    if redirect_enabled?
      task_id = @task&.id || sessions.first&.task_id
      respond_to do |format|
        format.html do
          if task_id.present?
            redirect_params = { session_id: params[:session_id] }.compact
            redirect_to repo_task_path(
              user_id: current_repository.owner_display_login,
              repository: current_repository.name,
              task_id: task_id,
              **redirect_params,
            ), status: :found
          else
            render_404
          end
        end
        format.json do
          result = prepare_task_response(sessions:, pull:, task: @task, route_id: "repoTaskRoute", token:)
          return unless result

          render_react_json(title: result[:title], payload: result[:payload])
        end
      end
      return
    end

    result = prepare_task_response(sessions:, pull:, task: @task, route_id: "repoTaskRoute", token:)
    return unless result

    respond_to do |format|
      format.html do
        render_react_html(
          title: result[:title],
          payload: result[:payload],
          app_name: self.class.react_bundle_name,
          page_data: PAGE_DATA_TASK,
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: result[:title], payload: result[:payload])
      end
    end
  end

  private

  def load_pull_request
    @pull = PullRequests::PullRequestAccessor.new.by_number(
      repository_id: current_repository.id,
      number: params[:pull_number].to_i,
    )
  rescue GH::Errors::ObjectNotFound
    render_404
  end

  def redirect_enabled?
    FeatureFlag.vexi.enabled?(:copilot_agents_pull_redirect_to_task, current_user, default: false)
  end

  # Fetches sessions linked to a pull request, handling UnauthorizedError
  # gracefully when the spinner flag is enabled.
  def fetch_sessions_for_pull(user:, pull:, token:)
    return [] unless pull

    CopilotSessions::AgentSession.for_pull_request(
      user:,
      pull:,
      token:,
      user_session:
    )
  rescue CopilotAPI::UnauthorizedError => e
    if FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
      log_capi_error("task.for_pull_request", e)
      []
    else
      raise
    end
  end

  # Finds the task that owns a given pull request by searching the current user's
  # recent PR-linked tasks in this repository. This is the fallback path for the
  # decoupled-PR flow where the session's resource fields were never populated.
  sig { params(user: User, pull: PullRequest, token: T.nilable(Copilot::EncryptedToken)).returns(T.nilable(CopilotSessions::TaskApi::Task)) }
  def find_task_for_pull_request(user:, pull:, token:)
    repository = current_repository
    owner = T.must(repository.owner)

    task_list = CopilotSessions::TaskApi::TaskList.for_repository(
      repository:,
      user:,
      token:,
      owner_filter: user.id,
      artifact_type: CopilotSessions::TaskApi::ArtifactType::PullRequest,
      page_size: 100,
      entry_point: :agents_controller_task_decoupled_fallback,
    )
    task = task_list.tasks.find { |t| t.pull_request_id == pull.id }
    return unless task

    capi = Copilot::User.copilot_api(
      user:,
      integration_id: CopilotAPI::COPILOT_SWE_AGENT,
      token:
    )
    task_response = T.unsafe(capi).get_task(
      owner_display_login: owner.display_login,
      repo: repository.name,
      task_id: task.id
    )
    CopilotSessions::TaskApi::Task.new(
      task_response.is_a?(ConcurrentFaraday::FutureResponse) ? task_response.value : task_response
    )
  rescue CopilotAPI::Error => e
    log_capi_error("find_task_for_pull_request", e)
    nil
  end
end
