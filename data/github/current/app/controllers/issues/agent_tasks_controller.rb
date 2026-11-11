# typed: strict
# frozen_string_literal: true

class Issues::AgentTasksController < IssuesController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include AgentInfoSerialization

  # Parent IssuesController rejects JSON on :index; this endpoint is JSON-only
  skip_before_action :reject_json_format_requests
  before_action :login_required
  before_action :require_copilot_swe_agent_enabled
  before_action :require_issue_cca_visualization

  depends_on_clusters \
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    optional: false, only: [:index]

  allow_verified_fetch only: [:index]

  sig { void }
  def index
    issue = find_issue
    return render_404 unless issue

    actor = T.must(current_user)

    fetch_tasks_from_agent_assignments(issue, actor)
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
    render json: { tasks: [], assigned_agents: [], issue_update_channel: GitHub::WebSocket::Channels.signed_issue(issue) }
  rescue CopilotAPI::NotFoundError
    render json: { tasks: [], assigned_agents: [], issue_update_channel: GitHub::WebSocket::Channels.signed_issue(issue) }
  rescue CopilotAPI::UnauthorizedError
    render json: { error: "Unauthorized to access agent tasks" }, status: :forbidden
  rescue CopilotAPI::NetworkError, CopilotAPI::RateLimitError, CopilotAPI::RequestError => e
    GitHub.logger.error(
      "exception.message": e.message,
      "code.namespace": "Issues::AgentTasksController",
      "code.function": "index",
    )
    render json: { error: "Unable to fetch agent tasks at this time" }, status: :service_unavailable
  end

  private

  sig { params(issue: Issue, actor: User).void }
  def fetch_tasks_from_agent_assignments(issue, actor)
    # Read task IDs from the agent_assignments table
    task_ids = AgentAssignment.where(
      source_repository_id: issue.repository_id,
      source_type: :issue,
      source_id: issue.id,
    ).pluck(:task_id).compact.uniq

    if task_ids.empty?
      render json: { tasks: [], assigned_agents: [], issue_update_channel: GitHub::WebSocket::Channels.signed_issue(issue) }
      return
    end

    # Fetch tasks via the batch endpoint
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: actor,
      entry_point: :issue_agent_tasks_index,
      user_session: user_session,
    )

    task_list = CopilotSessions::TaskApi::TaskList.batch_by_task_ids(
      user: actor,
      token: token,
      task_ids: task_ids,
      entry_point: :issue_agent_tasks_index,
    )

    render_tasks(task_list.tasks, actor, issue)
  end

  sig { params(task_objects: T::Array[CopilotSessions::TaskApi::Task], actor: User, issue: Issue).void }
  def render_tasks(task_objects, actor, issue)
    # Build Task objects and collect repo IDs
    task_objects = task_objects.select(&:repo_id)

    repo_ids = task_objects.map(&:repo_id).compact.uniq
    repos_by_id = Repository.where(id: repo_ids).index_by(&:id)

    # Check readability once per unique repo to avoid N+1 permission checks
    readable_promises = repos_by_id.map do |repo_id, repo|
      repo.async_readable_by?(actor).then { |readable| [repo_id, readable] }
    end
    readable_map = Promise.all(readable_promises).sync.to_h

    # Filter repos by readability, then apply conditional access policy filtering
    readable_repos = repos_by_id.values.select { |repo| readable_map[repo.id] }
    authorized_repos = cap_filter.authorized_resources(readable_repos)
    authorized_repo_ids = authorized_repos.map(&:id).to_set

    # Sort tasks in reverse chronological order by updated_at,
    # parsing the timestamp to avoid relying on lexicographic string ordering.
    task_objects = task_objects.sort_by do |task|
      timestamp = task.last_updated_at
      begin
        Time.iso8601(timestamp)
      rescue ArgumentError, TypeError
        # Fall back to the Unix epoch for blank/invalid timestamps so they end up last after reversing.
        Time.at(0)
      end
    end

    task_objects.reverse!

    # Filter tasks to only those in authorized repositories
    tasks = task_objects.filter_map do |task|
      repo = repos_by_id[task.repo_id]
      next nil unless repo && authorized_repo_ids.include?(task.repo_id)

      task.to_h.merge("url" => "/#{repo.name_with_display_owner}/tasks/#{task.id}")
    end

    # Collect unique Integration agent IDs from task agent_collaborators
    integration_ids = tasks.flat_map { |t| t["agent_collaborators"] || [] }
      .select { |ac| ac["agent_type"] == "Integration" }
      .filter_map { |ac| ac["agent_id"] }
      .uniq

    assigned_agents = integration_ids.filter_map do |integration_id|
      agent = AgenticApp.agent_for_integration_id(integration_id)
      serialize_agent_info(agent, viewer: actor) if agent
    end

    render json: { tasks: tasks, assigned_agents: assigned_agents, issue_update_channel: GitHub::WebSocket::Channels.signed_issue(issue) }

  end

  sig { returns(T.nilable(Issue)) }
  def find_issue
    issue_number = params[:issue_number].to_i
    return nil if issue_number.zero?

    current_repository.issues.find_by(number: issue_number)
  end

  sig { void }
  def require_copilot_swe_agent_enabled
    render_404 unless copilot_swe_agent_enabled?
  end

  sig { void }
  def require_issue_cca_visualization
    render_404 unless CopilotFeatureFlagsHelper.issue_cca_visualization_enabled?(current_user)
  end

  sig { returns(T::Boolean) }
  def copilot_swe_agent_enabled?
    current_repository.copilot_swe_agent_enabled?(current_user) || false
  end
end
