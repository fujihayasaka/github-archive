# typed: true
# frozen_string_literal: true

require "react_payload"

class Repos::Agents::TasksController < AbstractRepositoryController
  include Repos::Agents::Common
  include MissionControlExperimentEvents
  include AgentInfoSerialization

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
    ApplicationRecord::Iam,
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

    sig { params(base_props: T::Hash[Symbol, T.untyped], agents_enabled: T::Boolean, can_create_tasks: T::Boolean, tasks: T.untyped, member_request_entities: T::Hash[Symbol, T.untyped], agent_quota_snapshot: T.nilable(T::Hash[Symbol, T.untyped])).void }
    def initialize(base_props, agents_enabled:, can_create_tasks:, tasks:, member_request_entities:, agent_quota_snapshot:)
      @base_props = base_props
      @agents_enabled = agents_enabled
      @can_create_tasks = can_create_tasks
      @tasks = tasks
      @member_request_entities = member_request_entities
      @agent_quota_snapshot = agent_quota_snapshot
    end

    def payload
      @base_props.merge(
        agentsEnabled: @agents_enabled,
        canCreateTasks: @can_create_tasks,
        tasks: @tasks,
        memberRequestEntities: @member_request_entities,
        agentQuotaSnapshot: @agent_quota_snapshot,
      )
    end
  end

  # GET /:owner/:repo/agents
  def index
    user = T.must(current_user)

    emit_experiment_exposure(
      surface_type: :AGENT_SURFACE_TYPE_MISSION_CONTROL,
      entry_point: "repo_agents_index",
    )

    title = "Agents · #{current_repository.name_with_display_owner}"

    # Extract structured qualifiers (author:, is:) from the q param so they
    # are applied via the proper filter params rather than sent as free-text.
    q_qualifiers = parse_q_qualifiers

    author_param = params[:author]
    # Fall back to author extracted from q (e.g. "author:@me")
    q_author_logins = if author_param.blank? && q_qualifiers[:authors]&.any?
      q_qualifiers[:authors].map do |login|
        login == "@me" ? user.display_login : login
      end
    end

    filter_by_current_user = if q_author_logins&.any?
      q_author_logins.size == 1 && q_author_logins.first == user.display_login
    else
      author_param.present? && author_param == user.display_login
    end

    tasks, token = tasks(user: user, filter_by_current_user: filter_by_current_user, q_qualifiers: q_qualifiers, q_author_logins: q_author_logins)

    payload = IndexPayload.new(
      base_payload_props(user),
      agents_enabled: agents_enabled?,
      can_create_tasks: can_create_tasks?,
      tasks: tasks,
      member_request_entities: helpers.get_member_requests_payload(user),
      agent_quota_snapshot: agent_quota_snapshot_for_user(user),
    )

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: PAGE_DATA,
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  # GET /:owner/:repo/tasks/:task_id
  # rubocop:disable GitHub/UseRestfulActions
  def task
    user = T.must(current_user)
    token = CopilotSessions::CopilotApiToken.get_encrypted(user:, entry_point: :agents_controller_task, user_session: user_session)

    sessions = @task&.sessions || []

    result = prepare_task_response(sessions:, pull:, task: @task, route_id: "repoTaskByIdRoute", token:, task_id: params[:task_id])
    return unless result

    respond_to do |format|
      format.html do
        render_react_html(
          title: result[:title],
          payload: result[:payload],
          app_name: self.class.react_bundle_name,
          page_data: {
            hide_footer: true,
            selected_link: :repo_agents_task,
          },
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: result[:title], payload: result[:payload])
      end
    end
  end

  # GET /:owner/:repo/agents/pull/:pull_number/diff
  # TODO: Remove once task diffs are fully supported in the UI
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
  def task_diff
    render json: diff_data(current_repository, params[:base], params[:head])
  end

  private

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
    rescue CopilotAPI::UnauthorizedError => e # may be a passing 401 due to token eviction. We rescue to let the frontend retry
      log_capi_error("load_pull_request_from_task", e)
      render_404 unless FeatureFlag.vexi.enabled?(:copilot_mission_control_initial_data_spinner, current_user, default: false)
    rescue CopilotAPI::Error => e
      log_capi_error("load_pull_request_from_task", e)
      render_404
    rescue GH::Errors::ObjectNotFound => e
      log_capi_error("load_pull_request_from_task", e)
      render_404
    end
  end

  def tasks(user:, filter_by_current_user: false, q_qualifiers: {}, q_author_logins: nil)
    # Don't load tasks for users who can't actually use CCA (they'll see the upgrade blankslate)
    return [[], nil] unless user_can_use_cca?

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :agents_controller_index,
      user_session: user_session
    )

    creator_ids = resolve_creator_ids(user: user, filter_by_current_user: filter_by_current_user, q_author_logins: q_author_logins)
    type_param = params[:type]
    type_filter = type_param.is_a?(String) ? type_param.presence : nil
    # When filtering by code reviews, don't filter by archived status so both active and completed tasks are returned
    archived_filter = type_filter == "review" ? nil : (params[:closed] == "true" || params[:completed] == "true")

    # Apply is:open/is:closed from q qualifiers when no explicit closed/completed param
    if archived_filter == false && q_qualifiers[:is_state].present?
      archived_filter = q_qualifiers[:is_state] == "closed"
    end

    # Resolve agent groups from URL params to numeric integration IDs
    # Fall back to type: qualifiers from q when no explicit agent_group param
    include_agent_ids = if agent_filtering_enabled?
      ids = resolve_agent_ids_from_group_params
      if ids.nil? && q_qualifiers[:types]&.any?
        resolve_agent_ids_from_groups(q_qualifiers[:types])
      else
        ids
      end
    end

    # Parse filter params from the frontend for passthrough to CMC
    # Fall back to qualifiers from q when no explicit params are present
    session_states = parse_session_states
    if session_states.nil? && q_qualifiers[:statuses]&.any?
      parsed_states = q_qualifiers[:statuses].filter_map do |s|
        CopilotSessions::SessionState.try_deserialize(s)
      end
      session_states = parsed_states.presence
    end

    sort_field, sort_direction = parse_sort_params
    if sort_field.nil? && q_qualifiers[:sort] == "oldest"
      sort_field = CopilotSessions::TaskApi::SortField::LastUpdatedAt
      sort_direction = CopilotSessions::SortDirection::Asc
    end

    custom_agent_names = parse_custom_agent_names
    if custom_agent_names.nil? && q_qualifiers[:agents]&.any?
      custom_agent_names = q_qualifiers[:agents]
    end

    artifact_state = parse_artifact_state

    # CMC requires artifact_type when artifact_state is specified
    artifact_type = artifact_state.present? ? CopilotSessions::TaskApi::ArtifactType::PullRequest : nil

    # Use only free-text portion from q qualifiers (structured parts are
    # already applied via dedicated filter params above).
    # When q contains qualifiers, always use the parsed free_text (even if nil)
    # to avoid sending raw structured syntax to CMC.
    q_filter = if q_qualifiers.any?
      q_qualifiers[:free_text]
    else
      parse_q_param
    end

    # Best effort while the new API rolls out
    tasks = begin
      CopilotSessions::TaskApi::TaskList.for_repository(
        repository: current_repository,
        user:,
        token:,
        creator_ids:,
        archived_filter:,
        page_size: 10,
        type: type_filter,
        include_agent_ids:,
        session_states:,
        sort_field:,
        sort_direction:,
        custom_agent_names:,
        artifact_state:,
        artifact_type:,
        q: q_filter,
      ).tasks
    rescue
      []
    end

    [tasks.map(&:to_h), token]
  end

  def resolve_agent_ids_from_group_params
    group_param = params[:agent_group]
    return nil unless group_param.is_a?(String) && group_param.present?

    resolve_agent_ids_from_groups(group_param.split(",").map(&:strip))
  end

  # Resolves agent group names (e.g. "cloud", "cli", "vscode") to numeric integration IDs.
  def resolve_agent_ids_from_groups(group_names)
    return nil if group_names.blank?

    ids = group_names.flat_map do |name|
      group = AgenticApp::Group.try_deserialize(name.strip)
      next [] unless group

      AgenticApp.agents_for_group(group).filter_map do |agent|
        agent.integration&.id
      end
    end
    ids.uniq.presence
  end

  # Collects param values into an array, supporting both comma-separated and
  # repeated-param (with []) formats.
  # e.g., ?status=failed,in_progress → ["failed", "in_progress"]
  #        ?status[]=failed&status[]=in_progress → ["failed", "in_progress"]
  def collect_param_values(key)
    Array(params[key]).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:blank?)
  end

  # Parse status param (repeated params) into SessionState enums.
  # Unknown statuses (e.g., "merged", "closed") are silently dropped since they aren't valid CMC states.
  def parse_session_states
    raw = collect_param_values(:status)
    return nil if raw.empty?

    states = raw.filter_map do |s|
      CopilotSessions::SessionState.try_deserialize(s)
    end
    states.presence
  end

  # Parse sort params from the frontend. The FE sends order_by=oldest to sort ascending.
  def parse_sort_params
    order_by = params[:order_by]
    return [nil, nil] unless order_by.is_a?(String) && order_by.present?

    sort_field = CopilotSessions::TaskApi::SortField::LastUpdatedAt
    sort_direction = order_by == "oldest" ? CopilotSessions::SortDirection::Asc : CopilotSessions::SortDirection::Desc
    [sort_field, sort_direction]
  end

  # Parse custom_agent_name (repeated params)
  def parse_custom_agent_names
    collect_param_values(:custom_agent_name).presence
  end

  # Parse artifact_state param for passthrough to CMC.
  # Accepts comma-separated values (e.g., ?artifact_state=open,closed).
  VALID_ARTIFACT_STATES = Set.new(%w[open draft closed merged]).freeze
  private_constant :VALID_ARTIFACT_STATES

  def parse_artifact_state
    raw = collect_param_values(:artifact_state)
    return nil if raw.empty?

    valid = raw.select { |s| VALID_ARTIFACT_STATES.include?(s) }
    valid.join(",").presence
  end

  # Parse q (free-text search) param.
  # The frontend may encode structured qualifiers (e.g. "is:open author:@me")
  # into q. We extract known qualifiers so they can be applied via their
  # dedicated filter params and only pass remaining free-text to CMC.
  def parse_q_param
    raw = params[:q]
    return nil unless raw.is_a?(String)

    raw.strip.presence
  end

  # Extracts structured qualifiers from the q param and returns them as a hash.
  # Must stay in sync with the frontend's parseFilterQuery in filter-utils.ts.
  # Known qualifiers:
  #   is:open / is:closed              → :is_state
  #   author:<login> / author:@me      → :authors
  #   -author:<login>                  → :excluded_authors
  #   type:cloud / type:cli / type:vscode → :types (agent group filter)
  #   status:<status>                  → :statuses (detailed session states)
  #   agent:<slug>                     → :agents
  #   sort:oldest / sort:newest        → :sort
  # Any remaining tokens are treated as free-text search for CMC.
  def parse_q_qualifiers
    raw = params[:q]
    return {} unless raw.is_a?(String)

    tokens = raw.strip.split(/\s+/)
    authors = []
    excluded_authors = []
    types = []
    statuses = []
    agents = []
    is_state = T.let(nil, T.nilable(String))
    sort = T.let(nil, T.nilable(String))
    free_text_parts = []

    tokens.each do |token|
      case token
      when /\A-author:(.+)\z/i
        excluded_authors << $1
      when /\Aauthor:(.+)\z/i
        authors << $1
      when /\Ais:(open|closed)\z/i
        is_state = $1.downcase
      when /\Atype:(.+)\z/i
        types << $1.downcase
      when /\Astatus:(.+)\z/i
        statuses << $1.downcase
      when /\Aagent:(.+)\z/i
        agents << $1
      when /\Asort:(oldest|newest)\z/i
        sort = $1.downcase
      else
        free_text_parts << token
      end
    end

    result = {}
    result[:authors] = authors if authors.any?
    result[:excluded_authors] = excluded_authors if excluded_authors.any?
    result[:is_state] = is_state if is_state
    result[:types] = types if types.any?
    result[:statuses] = statuses if statuses.any?
    result[:agents] = agents if agents.any?
    result[:sort] = sort if sort
    result[:free_text] = free_text_parts.join(" ").presence
    result
  end

  # Resolves author login(s) from params to numeric user IDs for CMC's creator_id filter.
  # Supports repeated `author` params (e.g., ?author=octocat&author=monalisa).
  # Falls back to q_author_logins extracted from the q param when no explicit author param.
  def resolve_creator_ids(user:, filter_by_current_user: false, q_author_logins: nil)
    # Legacy behavior: filter_by_current_user means ?author=<current_user_login>
    return [user.id] if filter_by_current_user

    # Support comma-separated or repeated author params: ?author=octocat,monalisa
    author_params = Array(params[:author]).flat_map { |v| v.to_s.split(",") }.map(&:strip).select(&:present?)

    # Fall back to author logins extracted from the q param
    if author_params.empty? && q_author_logins&.any?
      author_params = q_author_logins
    end

    return nil if author_params.empty?

    ids = User.with_logins(author_params).pluck(:id).uniq
    ids.presence
  end

  sig { returns(T::Boolean) }
  def agent_filtering_enabled?
    FeatureFlag.vexi.enabled?(:copilot_mission_control_agent_filtering, current_user, default: false)
  end
end
