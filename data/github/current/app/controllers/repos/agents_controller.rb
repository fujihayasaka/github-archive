# typed: true
# frozen_string_literal: true

require "react_payload"

class Repos::AgentsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include MissionControlExperimentEvents

  DECOUPLED_PR_EXPERIMENT = AzureEXP::Experiments::MissionControlDecoupledPr

  before_action :login_required
  before_action :require_copilot_swe_agent_enabled
  before_action :load_current_pull_request, only: [:task, :pull_diff]

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
    only: [:index, :task, :pull_diff, :task_diff]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :task],
    optional: true

  class IndexPayload < ReactPayload::Base
    def route_id
      "repoAgentsRoute"
    end

    sig { params(repository: T.untyped, agents_enabled: T::Boolean, can_create_tasks: T::Boolean, current_user: User, pull_request_map: T.untyped, tasks: T.untyped, copilot_memory_enabled: T::Boolean, copilot_setup_steps_file_path: T.nilable(String), copilot_coding_agent_enabled: T::Boolean, has_paid_copilot_access: T::Boolean, has_ce_or_cb_access: T::Boolean, member_request_entities: T::Hash[Symbol, T.untyped], token: T.nilable(Copilot::EncryptedToken), sso_org_ids: T::Array[String]).void }
    def initialize(repository, agents_enabled, can_create_tasks, current_user, pull_request_map, tasks, copilot_memory_enabled, copilot_setup_steps_file_path, copilot_coding_agent_enabled, has_paid_copilot_access, has_ce_or_cb_access, member_request_entities, token:, sso_org_ids:)
      @repository = repository
      @agents_enabled = agents_enabled
      @can_create_tasks = can_create_tasks
      @current_user = current_user
      @pull_request_map = pull_request_map
      @tasks = tasks
      @copilot_memory_enabled = copilot_memory_enabled
      @copilot_setup_steps_file_path = copilot_setup_steps_file_path
      @copilot_coding_agent_enabled = copilot_coding_agent_enabled
      @has_paid_copilot_access = has_paid_copilot_access
      @has_ce_or_cb_access = has_ce_or_cb_access
      @member_request_entities = member_request_entities
      @token = token
      @sso_org_ids = sso_org_ids
    end

    def payload
      result = {
        repository: @repository,
        agentsEnabled: @agents_enabled,
        canCreateTasks: @can_create_tasks,
        currentUser: CopilotSessions::Payloads::PublicUser.new(@current_user).call,
        pullRequestMap: @pull_request_map,
        tasks: @tasks,
        copilotMemoryEnabled: @copilot_memory_enabled,
        copilotSetupStepsFilePath: @copilot_setup_steps_file_path,
        copilotCodingAgentEnabled: @copilot_coding_agent_enabled,
        hasPaidCopilotAccess: @has_paid_copilot_access,
        hasCEorCBAccess: @has_ce_or_cb_access,
        memberRequestEntities: @member_request_entities,
      }

      if @token
        result[:initialAuthToken] = {
          token: @token.value,
          expiration: @token.expiration&.iso8601,
          ssoOrgIDs: @sso_org_ids
        }
      end

      result
    end
  end

  class TaskPayload < ReactPayload::Base
    sig do
      params(
        pull: T.nilable(PullRequest),
        repository: T.untyped,
        current_user: User,
        current_user_can_push: T::Boolean,
        steering_enabled: T::Boolean,
        sessions: T.untyped,
        route_id: String,
        branch_alive_channel: T.untyped,
        task_id: T.nilable(String),
        task: T.untyped,
        token: T.nilable(Copilot::EncryptedToken),
        sso_org_ids: T::Array[String],
      ).void
    end
    def initialize(pull, repository, current_user, current_user_can_push, steering_enabled, sessions, route_id:, branch_alive_channel:, task_id:, task:, token:, sso_org_ids:)
      @pull = pull
      @repository = repository
      @current_user = current_user
      @current_user_can_push = current_user_can_push
      @steering_enabled = steering_enabled
      @sessions = sessions
      @route_id = route_id
      @branch_alive_channel = branch_alive_channel
      @task_id = task_id
      @task = task
      @token = token
      @sso_org_ids = sso_org_ids
    end

    def route_id
      @route_id
    end

    def payload
      result = {
        pull: @pull ? CopilotSessions::Payloads::Pull.new(pull_request: @pull, include_body: false, include_diff: false).call : nil,
        repository: @repository,
        currentUser: CopilotSessions::Payloads::PublicUser.new(@current_user).call,
        currentUserCanPush: @current_user_can_push,
        steeringEnabled: @steering_enabled,
        sessionOwners: CopilotSessions::AgentSession.get_session_owners(@sessions),
        agentMentions: @pull ? CopilotSessions::Helpers.get_agent_mentions_for_sessions(@sessions, @pull) : [],
        sessions: @sessions.map(&:session),
        branchAliveChannel: @branch_alive_channel,
        taskId: @task_id,
        task: @task&.to_h,
      }

      if @token
        result[:initialAuthToken] = {
          token: @token.value,
          expiration: @token.expiration&.iso8601,
          ssoOrgIDs: @sso_org_ids
        }
      end

      result
    end
  end

  def self.react_bundle_name
    "repo-agents"
  end

  # GET /:owner/:repo/agents
  def index
    user = T.must(current_user)
    decoupled_pr_mode = decoupled_pr_mode_enabled?(user)

    add_client_feature_flag([
      :copilot_swe_agent_progress_commands,
      :copilot_mission_control_decoupled_mode,
    ])
    add_decoupled_pr_client_feature_flags(decoupled_pr_mode)

    emit_experiment_exposure(
      surface_type: :AGENT_SURFACE_TYPE_MISSION_CONTROL,
      entry_point: "repo_agents_index",
    )
    # Skip exposure for staff-shipped users — they get the feature via the staff ship flag
    # and should not pollute experiment data.
    unless user.feature_flag_enabled?(DECOUPLED_PR_EXPERIMENT::STAFF_SHIP_FEATURE_FLAG, default: false)
      emit_experiment_exposure(
        surface_type: :AGENT_SURFACE_TYPE_MISSION_CONTROL,
        entry_point: "repo_agents_index",
        experiment: DECOUPLED_PR_EXPERIMENT,
      )
    end

    title = "Agents · #{current_repository.name_with_display_owner}"

    author_param = params[:author]
    filter_by_current_user = author_param.present? && author_param == user.display_login

    pull_request_map, tasks, token = tasks(user: user, filter_by_current_user: filter_by_current_user)

    payload = IndexPayload.new(
      repo_data,
      agents_enabled?,
      can_create_tasks?,
      user,
      pull_request_map,
      tasks,
      copilot_memory_enabled?,
      copilot_setup_steps_file_path,
      copilot_coding_agent_enabled?,
      has_paid_copilot_access?,
      has_ce_or_cb_access?,
      helpers.get_member_requests_payload(user),
      token: token,
      sso_org_ids: saml_for_user.protected_organization_ids.map(&:to_s),
    )

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: {
            hide_footer: true,
            selected_link: :repo_agents,
          },
          turbo: {
            id: "repo-content-turbo-frame",
            target: "_top",
            action: "advance",
          },
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  # GET /:owner/:repo/agents/pull/:pull_number
  # GET /:owner/:repo/tasks/:task_id
  # rubocop:disable GitHub/UseRestfulActions
  def task
    user = T.must(current_user)
    decoupled_pr_mode = decoupled_pr_mode_enabled?(user)

    add_client_feature_flag([
      :copilot_mission_control_link_to_sessions_in_repo,
      :copilot_mission_control_link_to_hyperspace,
    ])
    add_decoupled_pr_client_feature_flags(decoupled_pr_mode)

    emit_experiment_exposure(
      surface_type: :AGENT_SURFACE_TYPE_MISSION_CONTROL,
      entry_point: "repo_agents_task",
      session_id: params[:session_id],
    )
    # Skip exposure for staff-shipped users — they get the feature via the staff ship flag
    # and should not pollute experiment data.
    unless user.feature_flag_enabled?(DECOUPLED_PR_EXPERIMENT::STAFF_SHIP_FEATURE_FLAG, default: false)
      emit_experiment_exposure(
        surface_type: :AGENT_SURFACE_TYPE_MISSION_CONTROL,
        entry_point: "repo_agents_task",
        session_id: params[:session_id],
        experiment: DECOUPLED_PR_EXPERIMENT,
      )
    end

    title = pull ? "Agents · #{pull.title}" : "Agents · #{current_repository.name_with_display_owner}"

    token = CopilotSessions::CopilotApiToken.get_encrypted(user:, entry_point: :agents_controller_task, user_session: user_session)

    sessions = if @task.present? && @task.respond_to?(:sessions)
      @task.sessions
    elsif pull
      begin
        CopilotSessions::AgentSession.for_pull_request(
          user:,
          pull:,
          token:,
          user_session:
        )
      rescue CopilotAPI::UnauthorizedError # may be a passing 401 due to token eviction. We rescue to let the frontend retry
        if FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
          []
        else
          raise
        end
      end
    else
      []
    end

    if pull && sessions.empty? && params[:task_id].blank? && @task.blank? &&
        user.feature_flag_enabled?(:coding_agent_logs_in_pr, default: false)
      # Decoupled-PR fallback: the session was created before the PR existed, so
      # its resource_type/resource_id were never set and the resource-based lookup
      # returns nothing. Find the task that owns this PR via its artifacts instead.
      @task = find_task_for_pull_request(user:, pull:, token:)
      sessions = @task&.sessions || []
    end

    focused_session_id = params[:session_id]
    param_session_missing = sessions.none? { |session| session.id == focused_session_id }

    if (sessions.empty? || param_session_missing) && focused_session_id.present?
      begin
        session = CopilotSessions::AgentSession.for_session(
          user:,
          session_id: focused_session_id,
          user_session:,
          token:
        )
        sessions = [session].compact
      rescue CopilotAPI::UnauthorizedError # may be a passing 401 due to token eviction. We rescue to let the frontend retry
        unless FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
          raise
        end
      end
    end

    if sessions.empty? && !FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
      render_404
      return
    end

    route_id = params[:task_id].present? ? "repoTaskByIdRoute" : "repoTaskRoute"
    task_id = params[:task_id].present? ? params[:task_id] : sessions.first&.task_id

    branch_name = task_head_ref(@task) || @pull&.display_head_ref_name
    branch_alive_channel = branch_name ? GitHub::WebSocket::Channels.signed_branch(current_repository, branch_name) : nil

    # Build the app payload
    payload = TaskPayload.new(
      pull,
      repo_data,
      user,
      can_create_tasks?,
      steering_enabled?, # This is kind of redundant since we are blocking the page on the CCA policy, but keeping for consistency with MC and a future with other agents
      sessions,
      route_id: route_id,
      branch_alive_channel: branch_alive_channel,
      task_id: task_id,
      task: @task,
      token: token,
      sso_org_ids: saml_for_user.protected_organization_ids.map(&:to_s),
    )

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: {
            hide_footer: true,
            selected_link: :repo_agents_task,
          },
          turbo: {
            id: "repo-content-turbo-frame",
            target: "_top",
            action: "advance",
          },
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  # GET /:owner/:repo/agents/pull/:pull_number/diff
  # TODO: Remove once task diffs are fully supported in the UI
  # rubocop:disable GitHub/UseRestfulActions
  def pull_diff
    # For now, diffs are only available when we have a pull request
    # Future: tasks may have their own base/head refs independent of PRs
    unless @pull
      render json: nil
      return
    end

    render json: diff_data(current_repository, @pull.base_ref, @pull.head_ref)
  end

  # GET /:owner/:repo/tasks/:task_id/diff/:base...:head
  # rubocop:disable GitHub/UseRestfulActions
  def task_diff
    render json: diff_data(current_repository, params[:base], params[:head])
  end

  private

  def repo_data
    Repos::ReactPayload.current_repository_payload(
      current_repository,
      current_user_can_push: current_user_can_push?,
    )
  end

  def diff_data(repo, base_ref, head_ref)
    comparison = repo.comparison(base_ref, head_ref)

    unless comparison.valid? && !comparison.diffs.missing_commits? && comparison.viewable_by?(current_user)
      return nil
    end

    unless comparison.common_ancestor?
      return nil
    end

    if !comparison.diffs.available? || comparison.diffs.truncated_for_timeout?
      return nil
    end

    include_patch = params[:include_patch] == "true"

    diff_entries = comparison.diffs.entries

    if include_patch
      highlighter = SyntaxHighlightedDiff.new(repo)
      highlighter.highlight!(diff_entries)
    end

    # Extract file metadata and optional syntax-highlighted lines for each diff entry
    files = diff_entries.map do |diff|
      file_data = {
        path: diff.path,
        additions: diff.additions,
        deletions: diff.deletions,
        changes: diff.changes,
        status: diff.status,
        path_digest: diff.path_digest,
      }

      if include_patch && diff.text.try(:length).to_i > 0 && !diff.binary_text?
        file_data[:patch] = diff.unicode_text
        file_data[:lines] = highlighted_diff_lines(highlighter, diff)
      end

      file_data
    end

    # Calculate totals and return with diffs
    files.reduce({ files: files, additions: 0, deletions: 0, changes: 0 }) do |result, diff|
      result.merge(
        additions: result[:additions] + diff[:additions],
        deletions: result[:deletions] + diff[:deletions],
        changes: result[:changes] + diff[:changes]
      )
    end
  end

  def highlighted_diff_lines(highlighter, entry)
    parsed_lines = GitHub::Diff::RelatedLinesEnumerator.new(entry.lines)
    cache_code, html_lines = highlighter.frozen_colorized_lines_with_cache_code(entry)

    parsed_lines.map do |line|
      HighlightedDiffLine.for_line(line, html_lines: html_lines, cache_code: cache_code).as_json
    end
  end

  def load_current_pull_request
    if params[:task_id].present?
      load_pull_request_from_task
      return
    end

    begin
      @pull = PullRequests::PullRequestAccessor.new.by_number(
        repository_id: current_repository.id,
        number: params[:pull_number].to_i,
      )
    rescue GH::Errors::ObjectNotFound
      render_404
    end
  end

  def load_pull_request_from_task
    user = T.must(current_user)
    repository = current_repository
    owner = T.must(repository.owner)
    task_id = params[:task_id]

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :agents_controller_task,
      user_session:
    )

    begin
      capi = Copilot::User.copilot_api(
        user:,
        integration_id: CopilotAPI::COPILOT_SWE_AGENT,
        token:
      )
      task_response = T.unsafe(capi).get_task(
        owner_display_login: owner.display_login,
        repo: repository.name,
        task_id:
      )
      @task = CopilotSessions::TaskApi::Task.new(
        task_response.is_a?(ConcurrentFaraday::FutureResponse) ? task_response.value : task_response
      )

      pull_request_id = @task.pull_request_id

      # Pull request is optional - tasks may not have an associated PR yet
      return unless pull_request_id

      @pull = PullRequest.find_by(id: pull_request_id)

      return unless @pull

      if @pull.hide_from_user?(current_user)
        render_404
        nil
      end
    rescue CopilotAPI::UnauthorizedError # may be a passing 401 due to token eviction. We rescue to let the frontend retry
      render_404 unless FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
    rescue CopilotAPI::Error, GH::Errors::ObjectNotFound
      render_404
    end
  end

  def tasks(user:, filter_by_current_user: false)
    # Don't load tasks for users who can't actually use CCA (they'll see the upgrade blankslate)
    return [{}, [], nil] unless user_can_use_cca?

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :agents_controller_index,
      user_session: user_session
    )

    owner_filter = filter_by_current_user ? user.id : nil
    archived_filter = params[:closed] == "true" || params[:completed] == "true"

    # Best effort while the new API rolls out
    tasks = begin
      CopilotSessions::TaskApi::TaskList.for_repository(
        repository: current_repository,
        user:,
        token:,
        owner_filter: owner_filter,
        archived_filter:,
      ).tasks
    rescue
      []
    end

    pull_request_ids = tasks.filter_map(&:pull_request_id)

    pull_request_map = CopilotSessions::Public.id_to_pull_request_map(
      pull_request_ids:,
      user:,
      cap_filter: cap_filter,
      include_diff: true
    )

    [pull_request_map, tasks.map(&:to_h), token]
  end

  def task_head_ref(task)
    return nil unless task

    branch_artifact = task.artifacts.find do |artifact|
      artifact["provider"] == "github" &&
        artifact["type"] == "branch"
    end

    branch_artifact&.dig("data", "head_ref")
  end

  sig { params(user: User).returns(T::Boolean) }
  def decoupled_pr_mode_enabled?(user)
    DECOUPLED_PR_EXPERIMENT.active_for?(user) ||
      user.feature_flag_enabled?(DECOUPLED_PR_EXPERIMENT::STAFF_SHIP_FEATURE_FLAG, default: false)
  end

  sig { params(decoupled_pr_mode: T::Boolean).void }
  def add_decoupled_pr_client_feature_flags(decoupled_pr_mode)
    add_client_feature_flag([
      :copilot_mission_control_decoupled_mode,
      :copilot_authors_decoupled_pr,
    ]) do
      decoupled_pr_mode
    end
  end

  def require_copilot_swe_agent_enabled
    render_404 unless agents_enabled?
  end

  memoize def agents_enabled?
    # New flow: allow any Copilot user if owner has CCA enabled for repo
    if FeatureFlag.vexi.enabled?(:repo_agents_show_upgrade_slate, current_user, default: false)
      copilot_user = Copilot::Public::User.new(current_user)
      return false unless copilot_user.has_copilot_access?
      return false unless copilot_user.show_copilot_functionality?
      current_repository.owner&.copilot_swe_agent_enabled_for?(current_repository)
    else
      # Old flow: check if CCA is enabled for the repo and this specific viewer through their policy
      user_can_use_cca?
    end
  end

  # Strict check: user's own policy allows CCA on this repo
  memoize def user_can_use_cca?
    current_repository.copilot_swe_agent_enabled?(current_user)
  end

  memoize def steering_enabled?
    Copilot::Public::User.new(current_user).has_copilot_access?
  end

  memoize def can_create_tasks?
    current_user_can_push?
  end

  memoize def copilot_memory_enabled?
    current_copilot_user && current_repository.adminable_by?(current_user) && FeatureFlag.vexi.enabled?("copilot_memory_enablement_policy", current_user, default: false) &&
      Copilot::Policies::Memory.effective_value(current_copilot_user) == "enabled"
  end

  COPILOT_SETUP_STEPS_PATH = ".github/workflows/copilot-setup-steps.yml"

  memoize def copilot_setup_steps_file_path
    nwo = current_repository.name_with_display_owner
    default_branch = current_repository.default_branch

    return nil if !default_branch || !current_user_can_push? || !current_repository.includes_directory?(".github/workflows", default_branch)

    if current_repository.includes_file?(COPILOT_SETUP_STEPS_PATH, default_branch)
      "/#{nwo}/edit/#{default_branch}/#{COPILOT_SETUP_STEPS_PATH}"
    else
      "/#{nwo}/new/#{default_branch}/.github/workflows?filename=copilot-setup-steps.yml"
    end
  end

  memoize def copilot_coding_agent_enabled?
    current_repository.adminable_by?(current_user) &&
      current_repository.owner.copilot_swe_agent_enabled_for?(current_repository)
  end

  memoize def has_paid_copilot_access?
    copilot_user = current_copilot_user
    return false unless copilot_user

    copilot_user.has_paid_access?
  end

  memoize def has_ce_or_cb_access?
    copilot_user = current_copilot_user
    return false unless copilot_user

    copilot_user.has_ce_access? || copilot_user.has_cb_access?
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
  rescue CopilotAPI::Error
    nil
  end
end
