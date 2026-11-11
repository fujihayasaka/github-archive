# typed: true
# frozen_string_literal: true

require "react_payload"

class Repos::AgentsController < AbstractRepositoryController
  include ApplicationController::JsonDependency

  before_action :login_required
  before_action :require_repo_agents_view_enabled
  before_action :require_copilot_swe_agent_enabled
  before_action :load_current_pull_request, only: [:task]

  attr_reader :pull

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [].freeze

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    only: [:index, :task]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :task],
    optional: true

  class IndexPayload < ReactPayload::Base
    def route_id
      "repoAgentsRoute"
    end

    sig { params(repository: T.untyped, agents_enabled: T::Boolean, can_create_tasks: T::Boolean, current_user: T.untyped, pull_request_map: T.untyped, tasks: T.untyped).void }
    def initialize(repository, agents_enabled, can_create_tasks, current_user, pull_request_map, tasks)
      @repository = repository
      @agents_enabled = agents_enabled
      @can_create_tasks = can_create_tasks
      @current_user = current_user
      @pull_request_map = pull_request_map
      @tasks = tasks
    end

    def payload
      {
        repository: @repository,
        agentsEnabled: @agents_enabled,
        canCreateTasks: @can_create_tasks,
        currentUser: @current_user,
        pullRequestMap: @pull_request_map,
        tasks: @tasks,
      }
    end
  end

  class TaskPayload < ReactPayload::Base
    def route_id
      "repoTaskRoute"
    end

    sig { params(pull: PullRequest, repository: T.untyped, current_user: T.untyped, current_user_can_push: T::Boolean, steering_enabled: T::Boolean, sessions: T.untyped).void }
    def initialize(pull, repository, current_user, current_user_can_push, steering_enabled, sessions)
      @pull = pull
      @repository = repository
      @current_user = current_user
      @current_user_can_push = current_user_can_push
      @steering_enabled = steering_enabled
      @sessions = sessions
    end

    def payload
      {
        pull: CopilotSessions::Payloads::Pull.new(pull_request: @pull, include_body: true).call,
        repository: @repository,
        currentUser: @current_user,
        currentUserCanPush: @current_user_can_push,
        steeringEnabled: @steering_enabled,
        sessionOwners: CopilotSessions::AgentSession.get_session_owners(@sessions),
        agentMentions: CopilotSessions::Helpers.get_agent_mentions_for_sessions(@sessions, @pull),
        sessions: @sessions.map(&:session),
      }
    end
  end

  def self.react_bundle_name
    "repo-agents"
  end

  # GET /:owner/:repo/agents
  def index
    add_client_feature_flag([
      :copilot_swe_agent_progress_commands,
    ])

    title = "Agents · #{current_repository.name_with_display_owner}"
    user = T.must(current_user)
    pull_request_map, tasks = tasks(user: user)

    payload = IndexPayload.new(
      repo_data,
      agents_enabled?,
      can_create_tasks?,
      user_data,
      pull_request_map,
      tasks,
    )

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: {
            hide_footer: true,
          },
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  # GET /:owner/:repo/agents/pull/:pull_number
  # rubocop:disable GitHub/UseRestfulActions
  def task
    add_client_feature_flag([
      :copilot_swe_agent_progress_commands,
    ])

    title = "Agents · #{pull.title}"
    user = T.must(current_user)

    # Prefetch the sessions for the PR
    token = CopilotSessions::CopilotApiToken.get_encrypted(user:, entry_point: :agents_controller_task, user_session: user_session)
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

    # Redirect to the agents page if no sessions found for the pull request
    if sessions.empty?
      redirect_to repo_agents_path(current_repository.owner.display_login, current_repository.name)
      return
    end

    payload = TaskPayload.new(
      pull,
      repo_data,
      user_data,
      can_create_tasks?,
      steering_enabled?, # This is kind of redundant since we are blocking the page on the CCA policy, but keeping for consistency with MC and a future with other agents
      sessions,
    )

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: {
            hide_footer: true,
          },
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  private

  def repo_data
    Repos::ReactPayload.current_repository_payload(
      current_repository,
      current_user_can_push: current_user_can_push?,
    )
  end

  def user_data
    Repos::ReactPayload.current_user_payload(current_user).merge({
      isStaff: current_user.employee?,
    })
  end

  def load_current_pull_request
    begin
      @pull = PullRequests::PullRequestAccessor.new.by_number(
        repository_id: current_repository.id,
        number: params[:pull_number].to_i,
      )
    rescue GH::Errors::ObjectNotFound
      render_404
    end
  end

  def tasks(user:)
    return [{}, []] unless agents_enabled?
    CopilotSessions::DeprecatedTask.for_user_by_pull_requests(user:, user_session: user_session, cap_filter: cap_filter)
  end

  def require_repo_agents_view_enabled
    render_404 unless current_user.feature_flag_enabled?(:repo_agents_view, default: false)
  end

  def require_copilot_swe_agent_enabled
    render_404 unless agents_enabled?
  end

  memoize def agents_enabled?
    current_repository.copilot_swe_agent_enabled?(current_user)
  end

  memoize def steering_enabled?
    Copilot::Public::User.new(current_user).has_copilot_access?
  end

  memoize def can_create_tasks?
    current_user_can_push?
  end
end
