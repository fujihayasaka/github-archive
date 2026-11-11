# typed: strict
# frozen_string_literal: true

class Api::ConcurrencyGroups < Api::App
  include Api::App::TwirpHelpers
  include ActionsHelper

  # List concurrency groups for a repository.
  get "/repositories/:repository_id/actions/concurrency_groups", operation_id: "actions/list-concurrency-groups-for-repository" do
    repo = find_repo!
    feature_flag_or_404!(repo)

    control_access :read_actions,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?,
      forbid: repo.public?

    ensure_non_conflicting_cursor_params!
    if params[:before].present?
      # The run-service ListConcurrencyGroups API (called below) only supports forward cursor
      # pagination, so `before` cannot be honored here.
      deliver_error!(422, message: "The 'before' parameter is not supported on this endpoint; use 'after' for pagination.")
    end
    per_page = parse_per_page

    result = handle_twirp_errors do
      run_service_client.list_concurrency_groups(
        repository_global_id: repo.next_global_id,
        cursor: params[:after],
        limit: per_page
      )
    end

    next_cursor = result.next_cursor.presence
    if next_cursor
      links.add_current({ after: next_cursor, before: nil, page: nil }, rel: "next")
    end

    deliver :concurrency_groups_list_hash, {
      groups: result.groups,
      total_count: result.total_count,
      repo: repo,
    }.tap { record_endpoint_metric("list_for_repository", "filter:#{params[:after].present? ? 'after' : 'none'}") }
  end

  # Get a concurrency group for a repository.
  get "/repositories/:repository_id/actions/concurrency_groups/:group_name", operation_id: "actions/get-concurrency-group-for-repository" do
    repo = find_repo!
    feature_flag_or_404!(repo)

    control_access :read_actions,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?,
      forbid: repo.public?

    if params[:ahead_of_run].present? && params[:ahead_of_job].present?
      deliver_error!(422, message: "Please provide only one of 'ahead_of_run' or 'ahead_of_job'.")
    end

    ahead_of_run_id = parse_positive_integer_param!(params[:ahead_of_run], "ahead_of_run") if params[:ahead_of_run].present?
    ahead_of_job_id = parse_positive_integer_param!(params[:ahead_of_job], "ahead_of_job") if params[:ahead_of_job].present?

    # Validate that the referenced run/job exists and belongs to the repo before calling run-service.
    ahead_of_run = find_workflow_run_in_repo!(ahead_of_run_id, repo) if ahead_of_run_id
    ahead_of_job = find_job_in_repo!(ahead_of_job_id, repo) if ahead_of_job_id

    # Validate group membership from the run/job's own concurrency JSON before calling run-service.
    # These matcher checks inspect the run/job's own stored concurrency JSON,
    # so they run before the run-service call to avoid a wasted RPC when the
    # caller has obviously misused the filter. If the group doesn't exist at
    # all in run-service, the empty-group 404 below still fires for callers
    # whose run/job does list the group locally (matchers non-empty).
    ahead_matchers =
      if ahead_of_run
        matchers_for_run_in_group(ahead_of_run, params[:group_name]).tap do |m|
          deliver_error!(422, message: "The specified workflow run does not belong to concurrency group '#{params[:group_name]}'.") if m.empty?
        end
      elsif ahead_of_job
        matchers_for_job_in_group(ahead_of_job, params[:group_name]).tap do |m|
          deliver_error!(422, message: "The specified job does not belong to concurrency group '#{params[:group_name]}'.") if m.empty?
        end
      end

    result = handle_twirp_errors do
      run_service_client.get_concurrency_group(
        repository_global_id: repo.next_global_id,
        group_name: params[:group_name]
      )
    end

    # 404 if group is empty or doesn't exist
    if result.acquired_instance&.instance_id.blank? && result.waiting_instances.empty?
      deliver_error!(404)
    end

    items =
      if ahead_of_run
        filter_items_ahead!(result, ahead_matchers, not_in_group_message: "The specified workflow run does not belong to concurrency group '#{params[:group_name]}'.")
      elsif ahead_of_job
        filter_items_ahead!(result, ahead_matchers, not_in_group_message: "The specified job does not belong to concurrency group '#{params[:group_name]}'.")
      else
        default_items(result)
      end

    resolved = GitHub::WorkflowConcurrency.resolve_queue_items(items, repo)

    filter_tag =
      if ahead_of_run
        "ahead_of_run"
      elsif ahead_of_job
        "ahead_of_job"
      else
        "none"
      end
    deliver :concurrency_group_hash, {
      group_name: result.group_name,
      instances: resolved,
      total_count: resolved.length,
      repo: repo,
    }.tap { record_endpoint_metric("get_for_repository", "filter:#{filter_tag}") }
  end

  # List concurrency groups for a workflow run.
  get "/repositories/:repository_id/actions/runs/:run_id/concurrency_groups", operation_id: "actions/list-concurrency-groups-for-workflow-run" do
    repo = find_repo!
    feature_flag_or_404!(repo)

    control_access :read_actions,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?,
      forbid: repo.public?

    workflow_run = find_workflow_run_in_repo!(params[:run_id], repo)

    # Gather all concurrency group names from local data, sorted by name
    # for stable cursor-based pagination.
    #
    # `total` and the returned set are derived from the run's configuration,
    # not from run-service's live queue. A group is included even when the
    # run no longer has any items currently holding or waiting in it; in
    # that case the `group_members` array will be empty. This contract is
    # documented on the operation and response schema.
    all_candidates = GitHub::WorkflowConcurrency
      .run_concurrency_candidates(workflow_run)
      .sort_by { |c| c[:group_name] }
    total = all_candidates.length

    ensure_non_conflicting_cursor_params!
    per_page = parse_per_page

    if params[:after].present?
      all_candidates_after = all_candidates.drop_while { |c| c[:group_name] <= params[:after] }
      paged_candidates = all_candidates_after.first(per_page)
      has_next = all_candidates_after.length > per_page
      # Forward-only cursor: no prev link on after-paginated requests. Clients
      # that need to page backward should use `before=` from a forward page's
      # next cursor, not from an after-paginated response.
      has_prev = false
    elsif params[:before].present?
      all_candidates_before = all_candidates.select { |c| c[:group_name] < params[:before] }
      paged_candidates = all_candidates_before.last(per_page)
      has_next = all_candidates.any? { |c| c[:group_name] >= params[:before] }
      has_prev = all_candidates_before.length > per_page
    else
      paged_candidates = all_candidates.first(per_page)
      has_next = all_candidates.length > per_page
      has_prev = false
    end

    if has_next && (last_on_page = paged_candidates.last)
      links.add_current({ after: last_on_page[:group_name], before: nil, page: nil }, rel: "next")
    end
    if has_prev && (first_on_page = paged_candidates.first)
      links.add_current({ before: first_on_page[:group_name], after: nil, page: nil }, rel: "prev")
    end
    # Always emit a "first" link to opt out of the framework's default
    # page-based pagination headers, which don't apply to this cursor API.
    links.add_current({ after: nil, before: nil, page: nil }, rel: "first")

    # For each group on this page, query run-service and find this run's instances.
    # Any run-service failure surfaces as an error from build_run_group_entry,
    # ensuring total_count and the returned groups list stay in sync.
    #
    # Note: this is N+1 to run-service (one GetConcurrencyGroup RPC per group on
    # the page, issued serially). For runs participating in many groups this can
    # add latency; a batched run-service RPC could be a worthwhile follow-up.
    groups_data = paged_candidates.map do |candidate|
      build_run_group_entry(candidate, repo, workflow_run)
    end

    # Track run-service fan-out so we can spot per-request amplification
    # before considering a batched RPC.
    GitHub.dogstats.distribution(
      "api.concurrency_groups.list_for_workflow_run.run_service_fanout",
      paged_candidates.length
    )

    list_run_filter_tag =
      if params[:after].present?
        "after"
      elsif params[:before].present?
        "before"
      else
        "none"
      end
    deliver :run_concurrency_groups_hash, {
      groups: groups_data,
      total_count: total,
      repo: repo,
    }.tap { record_endpoint_metric("list_for_workflow_run", "filter:#{list_run_filter_tag}") }
  end

  private

  # Accessor for the parent app's `@links` ivar (set by middleware on each
  # request). Wrapped in a helper because `Api::App` does not expose a reader
  # and Sorbet `# typed: strict` requires explicit declarations for instance
  # variables.
  sig { returns(T.untyped) }
  def links
    # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods -- known ivar set by Api::App middleware
    T.unsafe(self).instance_variable_get(:@links)
    # rubocop:enable GitHub/AvoidDynamicInstanceVariableMethods
  end

  # Emit a per-endpoint success counter so we can track usage and outcomes
  # by operation as the new APIs roll out behind the feature flag. Only
  # success-path requests reach this; error responses go through
  # `deliver_error!` (which raises) and are tracked by the global API
  # middleware in `app/api/app.rb`.
  sig { params(operation: String, extra_tags: String).void }
  def record_endpoint_metric(operation, *extra_tags)
    GitHub.dogstats.increment(
      "api.concurrency_groups.request",
      tags: ["operation:#{operation}", "outcome:success", *extra_tags]
    )
  end

  sig { params(repo: Repository).void }
  def feature_flag_or_404!(repo)
    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:actions_concurrency_group_api, repo, default: false)
  end

  sig { void }
  def ensure_non_conflicting_cursor_params!
    if params[:after].present? && params[:before].present?
      deliver_error!(422, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  # Parse the per_page query parameter, mirroring Rest::Paginator semantics:
  # missing/non-numeric/<=0 falls back to the default, anything above the max
  # is silently capped.
  PER_PAGE_DEFAULT = 30
  PER_PAGE_MAX = 100
  sig { returns(Integer) }
  def parse_per_page
    value = params[:per_page].presence&.to_i
    return PER_PAGE_DEFAULT if value.nil? || value <= 0
    [value, PER_PAGE_MAX].min
  end

  # Parse a query parameter that must be a positive integer (e.g. a record
  # ID). Returns the parsed Integer, or 422s with a message naming the
  # parameter when the value is missing, non-numeric, zero, or negative.
  # Strict (\A\d+\z) so values like "0x1F", "+5", or " 5 " don't sneak
  # through.
  sig { params(value: T.untyped, name: String).returns(Integer) }
  def parse_positive_integer_param!(value, name)
    s = value.to_s
    unless s.match?(/\A\d+\z/) && s.to_i.positive?
      deliver_error!(422, message: "The '#{name}' parameter must be a positive integer.")
    end
    s.to_i
  end

  # Look up a workflow run by id and ensure it belongs to the given repo,
  # 404'ing on any failure.
  sig { params(run_id: T.untyped, repo: Repository).returns(Actions::WorkflowRun) }
  def find_workflow_run_in_repo!(run_id, repo)
    workflow_run = record_or_404(Actions::WorkflowRun.find_by(id: run_id, repository_id: repo.id))
    record_or_404(workflow_run.check_suite)
    workflow_run
  end

  # Look up a check_run (job) by id and ensure it belongs to the given repo,
  # 404'ing on any failure.
  sig { params(job_id: Integer, repo: Repository).returns(CheckRun) }
  def find_job_in_repo!(job_id, repo)
    job = record_or_404(Checks.domain.check_runs.for_id(job_id, repository_id: repo.id))
    ActiveRecord::Associations::Preloader.new(
      records: [job],
      associations: { check_suite: :workflow_run },
    ).call
    record_or_404(T.must(job.check_suite).workflow_run)
    job
  end

  # Build the unfiltered ordered items list: acquired first, then waiting by
  # position. Item display type (job / reusable_workflow / run) is resolved by
  # GitHub::WorkflowConcurrency.resolve_queue_items from the instance_id shape.
  sig do
    params(group_result: GitHub::ActionsRunService::Api::Twirp::V1::GetConcurrencyGroupResponse)
      .returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def default_items(group_result)
    items = []
    if (acquired = group_result.acquired_instance) && acquired.instance_id.present?
      items << { instance_id: acquired.instance_id, acquired: true }
    end
    group_result.waiting_instances.sort_by(&:position).each do |wi|
      next unless wi.instance_id.present?
      items << { instance_id: wi.instance_id, acquired: false }
    end
    items
  end

  # Filter items to those ahead of the matched instance, plus the matched
  # instance itself at the end. Resolves the position window from the
  # run-service group result for the given matchers, or 422 if the matched
  # item is not present in the queue.
  sig do
    params(
      group_result: GitHub::ActionsRunService::Api::Twirp::V1::GetConcurrencyGroupResponse,
      matchers: T::Array[GitHub::WorkflowConcurrency::ConcurrencyMatcher],
      not_in_group_message: String,
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def filter_items_ahead!(group_result, matchers, not_in_group_message:)
    position_data = GitHub::WorkflowConcurrency.match_instance_in_group(group_result, matchers)
    deliver_error!(422, message: not_in_group_message) if position_data.nil?
    build_filter_items(position_data)
  end

  # Build the items list returned to resolve_queue_items for ahead_of_*
  # filtered responses: items strictly ahead of the matched instance, then the
  # matched instance itself last.
  sig { params(position_data: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def build_filter_items(position_data)
    items = position_data[:items_ahead].map do |i|
      { instance_id: i[:instance_id], acquired: i[:acquired] }
    end
    matched = position_data[:matched]
    items << { instance_id: matched[:instance_id], acquired: (matched[:status] == "in_progress") }
    items
  end

  # Matchers for a workflow_run in a specific group_name (used by ahead_of_run).
  # Excludes job-level matchers — a job-level lease blocks a single job, not
  # the run as a whole.
  sig { params(workflow_run: Actions::WorkflowRun, group_name: String).returns(T::Array[GitHub::WorkflowConcurrency::ConcurrencyMatcher]) }
  def matchers_for_run_in_group(workflow_run, group_name)
    group = GitHub::WorkflowConcurrency
      .run_concurrency_candidates(workflow_run)
      .find { |g| g[:group_name] == group_name }
    return [] unless group

    group[:matchers].reject { |m| m[:level] == "job" }
  end

  # Matchers for a single job in a specific group_name (used by ahead_of_job).
  # Includes the job's own job-level matcher and any reusable-workflow matcher
  # on an ancestor path of the job.
  sig { params(job: CheckRun, group_name: String).returns(T::Array[GitHub::WorkflowConcurrency::ConcurrencyMatcher]) }
  def matchers_for_job_in_group(job, group_name)
    workflow_run = T.must(job.check_suite).workflow_run
    job_run = job.workflow_job_run
    return [] unless workflow_run && job_run

    group = GitHub::WorkflowConcurrency
      .run_concurrency_candidates(workflow_run)
      .find { |g| g[:group_name] == group_name }
    return [] unless group

    ext_id = T.must(job.check_suite).external_id.to_s
    expected_job_instance_id = "#{ext_id}.#{job_run.job_key}"
    ancestor_paths = job_run.reusable_job? ? GitHub::WorkflowConcurrency.reusable_ancestor_paths(job_run) : []
    rwf_instance_ids = ancestor_paths.map { |p| "#{ext_id}.#{p}" }

    group[:matchers].select do |m|
      case m[:level]
      when "job"
        m[:instance_id] == expected_job_instance_id
      when "reusable_workflow"
        rwf_instance_ids.include?(m[:instance_id])
      else
        false
      end
    end
  end

  sig { returns(ActionsRunService::Twirp::RunServiceClient) }
  def run_service_client
    @run_service_client ||= T.let(
      ActionsRunService::Twirp::RunServiceClient.new(base_url: GitHub.actions_run_service_address),
      T.nilable(ActionsRunService::Twirp::RunServiceClient),
    )
  end

  # Build a group entry for the run's concurrency groups list response.
  # Surfaces run-service failures via handle_twirp_errors so total_count and
  # the returned groups list cannot drift out of sync.
  sig do
    params(
      candidate: GitHub::WorkflowConcurrency::RunConcurrencyGroup,
      repo: Repository,
      workflow_run: Actions::WorkflowRun,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def build_run_group_entry(candidate, repo, workflow_run)
    group_status = handle_twirp_errors do
      run_service_client.get_concurrency_group(
        repository_global_id: repo.next_global_id,
        group_name: candidate[:group_name]
      )
    end

    matchers_by_id = candidate[:matchers].index_by { |m| m[:instance_id] }

    instances = []

    if group_status.acquired_instance&.instance_id.present?
      iid = group_status.acquired_instance.instance_id
      matcher = matchers_by_id[iid]
      if matcher
        entry = build_run_instance(iid, "in_progress", 0, workflow_run, matcher)
        instances << entry if entry
      end
    end

    group_status.waiting_instances.sort_by(&:position).each do |wi|
      next unless wi.instance_id.present?
      matcher = matchers_by_id[wi.instance_id]
      next unless matcher
      entry = build_run_instance(wi.instance_id, "pending", wi.position, workflow_run, matcher)
      instances << entry if entry
    end

    {
      group_name: candidate[:group_name],
      items: instances,
    }
  end

  # Construct a single item entry for the list-concurrency-groups-for-workflow-run
  # response, resolving job/run details appropriate for the lease level.
  # Returns nil for job/reusable_workflow leases when the check_run cannot be
  # resolved (e.g. the wjr was deleted, or run-service is ahead of our replica),
  # because such items have no usable position_url and no identifying job
  # fields. Dropping them keeps position_url non-nilable in the response.
  sig do
    params(
      instance_id: String,
      status: String,
      position: Integer,
      workflow_run: Actions::WorkflowRun,
      matcher: GitHub::WorkflowConcurrency::ConcurrencyMatcher,
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def build_run_instance(instance_id, status, position, workflow_run, matcher)
    entry = {
      run_id: workflow_run.id,
      run_name: workflow_run.name,
      run_url: workflow_run.permalink(include_host: false),
      status: status,
      position: position,
      level: matcher[:level],
    }

    case matcher[:level]
    when "job"
      job_key = instance_id.split(".", 2).second
      return nil if job_key.blank?
      wjr = workflow_run.latest_workflow_job_runs.find_by(job_key: job_key)
      return nil unless wjr&.check_run
      attach_job_details(entry, wjr.check_run)
    when "reusable_workflow"
      path = matcher[:rwf_path]
      return nil if path.blank?
      caller_job_run = GitHub::WorkflowConcurrency.find_reusable_caller_job_run(
        workflow_run.latest_workflow_job_runs, path
      )
      return nil unless caller_job_run&.check_run
      attach_job_details(entry, caller_job_run.check_run)
    end

    entry
  end

  sig { params(entry: T::Hash[Symbol, T.untyped], check_run: T.nilable(CheckRun)).void }
  def attach_job_details(entry, check_run)
    return unless check_run
    entry[:job_id] = check_run.id
    entry[:job_name] = check_run.display_name
    entry[:job_url] = check_run.permalink(include_host: false)
  end
end
