# typed: true
# frozen_string_literal: true

module GitHub::WorkflowConcurrency
  # The BlockingItem type contains resolved details about an item in a concurrency group
  # that is blocking the current workflow run or job run.
  #
  # Properties:
  #   - check_suite_id: blocking check suite id
  #   - check_run_id: present for job and reusable workflow items (for the latter this is the calling job)
  #   - acquired: true when this item is the currently acquired lease holder
  #   - blocked_at_level: "job" or "workflow" indicates what level of the current run is blocked
  #   - workflow_run_id: blocking workflow run id
  #   - workflow_run_name: blocking workflow run name
  #   - workflow_run_run_number: blocking workflow run number
  #   - workflow_run_explicit_name: whether the workflow run name came from run-name
  #   - workflow_run_url: workflow run permalink
  #   - display_name: primary display name of the blocking item
  #   - url: permalink for the blocking (job or workflow run) item
  #   - display_type: "job", "reusable_workflow", or "run"
  BlockingItem = T.type_alias do
    {
      check_suite_id: Integer,
      check_run_id: T.nilable(Integer),
      acquired: T::Boolean,
      blocked_at_level: T.nilable(String),
      workflow_run_id: T.nilable(Integer),
      workflow_run_name: T.nilable(String),
      workflow_run_run_number: T.nilable(Integer),
      workflow_run_explicit_name: T.nilable(T::Boolean),
      workflow_run_url: T.nilable(String),
      display_name: T.nilable(String),
      url: String,
      display_type: String,
    }
  end

  BlockingItemsResult = T.type_alias do
    {
      items: T::Array[BlockingItem],
      total_count: Integer,
    }
  end

  JobBlockingItemsResult = T.type_alias do
    {
      items: T::Array[BlockingItem],
      blocked_at_level: T.nilable(String),
      total_count: Integer,
    }
  end

  # Controls how a candidate identifies the current waiting item in the
  # run-service queue for a concurrency group.
  class CandidateMatchMode < T::Enum
    enums do
      ExactInstanceId = new("exact_instance_id")
      ExternalIdPrefix = new("external_id_prefix")
    end
  end

  # Describes one concurrency group lookup, including both the user-facing
  # blocked level and the queue matching strategy for the current run.
  class ConcurrencyCandidate < T::Struct
    const :concurrency_str, T.nilable(String)
    const :level, String
    const :job_key, T.nilable(String)
    const :match_mode, CandidateMatchMode

    sig { returns(T.nilable(String)) }
    def group_name
      concurrency_value = concurrency_str
      return nil if concurrency_value.nil? || concurrency_value.empty?

      JSON.parse(concurrency_value).dig("group")
    rescue
      nil
    end
  end

  # Instance IDs from the run-service are "{plan_id}" or "{plan_id}.{id_path}",
  # where plan_id = check_suite.external_id (a UUID) and id_path is the
  # dot-joined node-ref IDs for the target node (see run-service ids.GetInstanceID).
  #
  # There are three concurrency lease types, each with a different id_path:
  #
  #   PlanGroupLease (workflow-level concurrency):
  #     "{plan_id}"                                        (no id_path)
  #
  #   JobGroupLease (job-level concurrency):
  #     "{plan_id}.{job_template}.{job_id}"                e.g. "{plan}.build.__default"
  #     "{plan_id}.{rwf}.{job_template}.{job_id}"          e.g. "{plan}.deploy.build.__default"
  #     (job_id is "__default" for non-matrix, or the matrix key e.g. "x64")
  #
  #   ReusableWorkflowGroupLease (reusable-workflow-level concurrency):
  #     "{plan_id}.{rwf}"                                  e.g. "{plan}.deploy"
  #     "{plan_id}.{rwf_template}.{rwf_id}"                e.g. "{plan}.deploy.__default" (with strategy)
  #
  # The monolith stores the full id_path as WorkflowJobRun.job_key,
  # e.g. job_key = "build.__default" or "deploy.build.__default".
  #
  # For ReusableWorkflowGroupLease, the id_path (e.g. "deploy") is a strict
  # prefix of the stored job_key (e.g. "deploy.build.__default"), so we use
  # prefix matching (job_key LIKE "{id_path}.%") to resolve to a specific job.

  # Parses a run-service instance_id into [external_id, id_path].
  # "ext-123.build.__default" → ["ext-123", "build.__default"]
  # "ext-123" → ["ext-123", nil]
  def self.parse_instance_id(instance_id)
    instance_id.split(".", 2)
  end
  private_class_method :parse_instance_id

  # Maximum number of queue items to resolve to DB records.
  # While concurrency queues are limited to 100 items in run-service, a workflow run can be
  # blocked by multiple concurrency groups and the union of their queues can exceed 100 items.
  # This constant acts as a hard cap on how many items we resolve to DB records for display purposes,
  # to prevent excessive memory usage and long response times in extreme cases.
  MAX_RESOLVE_LIMIT = 100

  # Iterates through concurrency group candidates, queries GetConcurrencyGroup for each,
  # and collects the resolved blocking items.
  #
  # Each candidate describes one concurrency group to query, including the
  # display level and how to match the current waiting instance.
  #
  # Parameters:
  #   - check_suite: the check suite context for this lookup (required)
  #
  # Options:
  #   - exclude_external_id: reject items from this check_suite by matching the
  #     external_id prefix of instance_ids (e.g. same-run exclusion)
  #   - resolve_limit: only resolve the first N items from the queue (for display);
  #     remaining items are counted but not DB-resolved. nil or values above
  #     MAX_RESOLVE_LIMIT are capped to MAX_RESOLVE_LIMIT.
  #
  # Returns a hash with:
  #   - items: array of resolved blocking items in queue order
  #   - total_count: total number of blocking items ahead of the current item,
  #     including items not resolved because of resolve_limit
  sig do
    params(
      candidates: T::Array[ConcurrencyCandidate],
      check_suite: T.untyped,
      exclude_external_id: T.untyped,
      resolve_limit: T.nilable(Integer),
    ).returns(BlockingItemsResult)
  end
  def self.blocking_items(candidates, check_suite, exclude_external_id: nil, resolve_limit: nil)
    raw_items = []
    processed_groups = Set.new
    run_service_client = ActionsRunService.client_for_url(
      url: check_suite&.workflow_run&.latest_workflow_run_execution&.run_stamp_url,
      use_lab: check_suite&.lab_workflow? || false
    )

    candidates.each do |candidate|
      group = candidate.group_name
      next unless group.present?

      # De-duplicate by [group, job_key, match mode] so that job-level and
      # workflow-level candidates sharing the same group name are both
      # processed. They can use different current-item matching rules, so a
      # miss in one mode must not prevent the other from running.
      dedup_key = [group, candidate.job_key, candidate.match_mode]
      next if processed_groups.include?(dedup_key)
      processed_groups.add(dedup_key)

      group_items = queue_items_ahead(
        candidate.concurrency_str, check_suite&.repository, check_suite&.external_id,
        current_job_key: candidate.job_key,
        match_by_external_id_prefix: candidate.match_mode == CandidateMatchMode::ExternalIdPrefix,
        run_service_client: run_service_client
      )
      group_items.each { |item| item[:blocked_at_level] = candidate.level }
      raw_items.concat(group_items)
    end

    # Exclude items from the specified check_suite by matching external_id prefix
    if exclude_external_id
      ext_str = exclude_external_id.to_s
      raw_items = raw_items.reject { |r| parse_instance_id(r[:instance_id]).first == ext_str }
    end

    # Dedup by instance_id (same instance always resolves to the same record)
    seen_ids = Set.new
    raw_items = raw_items.select { |r| seen_ids.add?(r[:instance_id]) }

    total_count = raw_items.length
    effective_limit = [resolve_limit || MAX_RESOLVE_LIMIT, MAX_RESOLVE_LIMIT].min
    items_to_resolve = raw_items.first(effective_limit)

    T.let({ items: resolve_queue_items(items_to_resolve, check_suite&.repository), total_count: total_count }, BlockingItemsResult)
  end

  # API-based blocking items for the workflow run page.
  # Aggregates all concurrency groups (workflow + each unique pending job group).
  # Returns a sorted, deduped array of items with :blocked_at_level annotations.
  sig { params(check_suite: T.untyped, resolve_limit: T.nilable(Integer)).returns(BlockingItemsResult) }
  def self.workflow_blocking_items(check_suite, resolve_limit: nil)
    workflow_run = check_suite&.workflow_run
    return T.let({ items: [], total_count: 0 }, BlockingItemsResult) unless workflow_run

    candidates = T.let([], T::Array[ConcurrencyCandidate])
    wf = workflow_run.concurrency
    if wf.present?
      candidates << ConcurrencyCandidate.new(
        concurrency_str: wf,
        level: "workflow",
        job_key: nil,
        match_mode: CandidateMatchMode::ExactInstanceId,
      )
    end

    check_suite.latest_check_runs do |check_runs|
      check_runs.includes(:workflow_job_run)
    end
      .filter_map { |cr| cr.workflow_job_run&.concurrency if cr.pending? }
      .uniq
      .each do |concurrency_str|
        candidates << ConcurrencyCandidate.new(
          concurrency_str: concurrency_str,
          level: "job",
          job_key: nil,
          match_mode: CandidateMatchMode::ExternalIdPrefix,
        )
      end

    blocking_items(candidates, check_suite, exclude_external_id: check_suite.external_id, resolve_limit: resolve_limit)
  end

  # API-based blocking items for the job detail page.
  # Includes direct job concurrency, any reusable-workflow ancestor concurrency,
  # and top-level workflow concurrency.
  # Returns { items: [...], blocked_at_level: "job"|"workflow"|nil }.
  sig { params(check_suite: T.untyped, check_run: T.untyped, resolve_limit: T.nilable(Integer)).returns(JobBlockingItemsResult) }
  def self.job_blocking_items(check_suite, check_run, resolve_limit: nil)
    candidates = job_blocking_candidates(check_suite, check_run)

    result = blocking_items(candidates, check_suite, resolve_limit: resolve_limit)

    T.let(
      {
        items: result[:items],
        blocked_at_level: result[:items].first&.dig(:blocked_at_level),
        total_count: result[:total_count],
      },
      JobBlockingItemsResult,
    )
  end

  def self.job_blocking_candidates(check_suite, check_run)
    candidates = T.let([], T::Array[ConcurrencyCandidate])
    job_run = check_run.workflow_job_run

    candidates << ConcurrencyCandidate.new(
      concurrency_str: job_run&.concurrency,
      level: "job",
      job_key: job_run&.job_key,
      match_mode: CandidateMatchMode::ExactInstanceId,
    )
    candidates.concat(reusable_workflow_blocking_candidates(check_suite, job_run))
    candidates << ConcurrencyCandidate.new(
      concurrency_str: check_suite.workflow_run&.concurrency,
      level: "workflow",
      job_key: nil,
      match_mode: CandidateMatchMode::ExactInstanceId,
    )

    candidates
  end

  def self.reusable_workflow_blocking_candidates(check_suite, job_run)
    return [] unless job_run&.reusable_job?

    latest_check_runs = check_suite.latest_check_runs do |check_runs|
      check_runs.includes(:workflow_job_run)
    end
    workflow_job_runs = latest_check_runs.filter_map(&:workflow_job_run)
    candidates = T.let([], T::Array[ConcurrencyCandidate])
    seen_candidates = Set.new

    reusable_ancestor_paths(job_run).each do |path|
      caller_job_run = find_reusable_caller_job_run(workflow_job_runs, path)
      next unless caller_job_run&.concurrency.present?

      [caller_job_run.job_key, path].each do |candidate_path|
        next unless candidate_path.present?

        dedup_key = [caller_job_run.concurrency, candidate_path]
        next unless seen_candidates.add?(dedup_key)

        candidates << ConcurrencyCandidate.new(
          concurrency_str: caller_job_run.concurrency,
          level: "job",
          job_key: candidate_path,
          match_mode: CandidateMatchMode::ExactInstanceId,
        )
      end
    end

    candidates
  end

  def self.reusable_ancestor_paths(job_run)
    parent_path = job_run.parent_job_id.to_s
    return [] if parent_path.blank?

    parts = parent_path.split(".")
    paths = []

    while parts.length > 1
      parts = parts[0...-1]
      paths << parts.join(".")
    end

    paths
  end

  def self.find_reusable_caller_job_run(workflow_job_runs, path)
    workflow_job_runs
      .select do |workflow_job_run|
        job_key = workflow_job_run.job_key.to_s
        job_key.present? && job_key.start_with?("#{path}.")
      end
      .min_by do |workflow_job_run|
        [id_path_depth(workflow_job_run.job_key), workflow_job_run.id]
      end
  end

  # Describes one expected run-service queue item for a workflow run.
  #   - instance_id: the exact id we expect to find in the queue (e.g. "{ext}",
  #     "{ext}.{job_key}", or "{ext}.{path}" for a reusable workflow lease)
  #   - level: "workflow", "job", or "reusable_workflow"
  #   - rwf_path: only set for level == "reusable_workflow"; the id_path
  #     fragment after the external_id (e.g. "deploy") used to resolve the
  #     caller job for display.
  ConcurrencyMatcher = T.type_alias do
    {
      instance_id: String,
      level: String,
      rwf_path: T.nilable(String),
    }
  end

  # One concurrency group that a workflow run participates in, plus all the
  # run-service instance ids we expect to see for that run in that group's queue.
  RunConcurrencyGroup = T.type_alias do
    {
      group_name: String,
      matchers: T::Array[ConcurrencyMatcher],
    }
  end

  # Enumerate every concurrency group a workflow run participates in, along
  # with the run-service instance ids we expect to find for that run.
  #
  # Groups are derived from the run's configuration across all of its latest
  # jobs, regardless of job status. A group can therefore be returned even
  # when its job has already completed and released its lease; callers that
  # only want active groups must filter by querying run-service.
  #
  # Covers all three lease shapes from run-service:
  #   - workflow-level     ({ext})            from workflow_run.concurrency
  #   - job-level          ({ext}.{job_key})  from each job's concurrency
  #   - reusable-workflow  ({ext}.{path})     from caller jobs' concurrency,
  #                                           one entry per reusable ancestor
  #                                           path reachable from a job
  #
  # Multiple matchers can share the same group_name (e.g. workflow- and
  # job-level concurrency targeting the same group); they are merged into one
  # RunConcurrencyGroup.
  sig { params(workflow_run: T.nilable(Actions::WorkflowRun)).returns(T::Array[RunConcurrencyGroup]) }
  def self.run_concurrency_candidates(workflow_run)
    check_suite = workflow_run&.check_suite
    return [] unless check_suite

    ext_id = check_suite.external_id.to_s
    groups = T.let({}, T::Hash[String, RunConcurrencyGroup])
    seen_instance_ids = T.let({}, T::Hash[String, T::Set[String]])

    add_matcher = lambda do |group_name, matcher|
      next if group_name.blank?
      seen = (seen_instance_ids[group_name] ||= Set.new)
      next unless seen.add?(matcher[:instance_id])
      entry = groups[group_name] ||= { group_name: group_name, matchers: [] }
      entry[:matchers] << matcher
    end

    wf_group = parse_concurrency_group(workflow_run.concurrency)
    add_matcher.call(wf_group, instance_id: ext_id, level: "workflow", rwf_path: nil)

    latest_check_runs = check_suite.latest_check_runs do |check_runs|
      check_runs.includes(:workflow_job_run)
    end
    workflow_job_runs = latest_check_runs.filter_map(&:workflow_job_run)

    workflow_job_runs.each do |wjr|
      next unless wjr.job_key.present?

      job_group = parse_concurrency_group(wjr.concurrency)
      add_matcher.call(job_group, instance_id: "#{ext_id}.#{wjr.job_key}", level: "job", rwf_path: nil)
    end

    # Reusable-workflow leases: walk each pending job's reusable ancestor paths,
    # find the caller workflow_job_run for each path, and emit a matcher when
    # the caller declares concurrency.
    seen_paths = Set.new
    workflow_job_runs.each do |wjr|
      next unless wjr.reusable_job?

      reusable_ancestor_paths(wjr).each do |path|
        next unless seen_paths.add?(path)

        caller = find_reusable_caller_job_run(workflow_job_runs, path)
        next unless caller&.concurrency.present?

        rwf_group = parse_concurrency_group(caller.concurrency)
        add_matcher.call(
          rwf_group,
          instance_id: "#{ext_id}.#{path}",
          level: "reusable_workflow",
          rwf_path: path,
        )
      end
    end

    groups.values
  end

  # Look up the matched item for a workflow run inside a single concurrency
  # group's queue, and the items strictly ahead of it.
  #
  # `matchers` enumerates the candidate instance_ids for the run in this
  # group; the first matcher whose instance_id appears in the queue wins.
  #
  # Returns:
  #   {
  #     matched: { instance_id:, position:, status:, level: },
  #     items_ahead: [{ instance_id:, acquired: }, ...],
  #   }
  # or nil if no matcher is present in the queue.
  sig do
    params(
      group_result: GitHub::ActionsRunService::Api::Twirp::V1::GetConcurrencyGroupResponse,
      matchers: T::Array[ConcurrencyMatcher],
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def self.match_instance_in_group(group_result, matchers)
    return nil if matchers.empty?

    matchers_by_id = matchers.index_by { |m| m[:instance_id] }

    acquired_id = group_result.acquired_instance&.instance_id
    if acquired_id.present? && matchers_by_id.key?(acquired_id)
      return {
        matched: {
          instance_id: acquired_id,
          position: 0,
          status: "in_progress",
          level: matchers_by_id[acquired_id][:level],
        },
        items_ahead: [],
      }
    end

    # Single sorted pass: accumulate ahead-of items until we hit a matcher.
    items_ahead = []
    if acquired_id.present?
      items_ahead << { instance_id: acquired_id, acquired: true }
    end

    group_result.waiting_instances.sort_by(&:position).each do |wi|
      next unless wi.instance_id.present?
      if matchers_by_id.key?(wi.instance_id)
        return {
          matched: {
            instance_id: wi.instance_id,
            position: wi.position,
            status: "pending",
            level: matchers_by_id[wi.instance_id][:level],
          },
          items_ahead: items_ahead,
        }
      end
      items_ahead << { instance_id: wi.instance_id, acquired: false }
    end

    nil
  end

  # Parse a JSON-encoded concurrency hash (as stored on workflow_run /
  # workflow_job_run) and return the group name, or nil if the value is
  # missing, malformed JSON, or not a JSON object.
  sig { params(concurrency_str: T.nilable(String)).returns(T.nilable(String)) }
  def self.parse_concurrency_group(concurrency_str)
    return nil if concurrency_str.blank?
    parsed = JSON.parse(concurrency_str)
    return nil unless parsed.is_a?(Hash)
    parsed["group"]
  rescue JSON::ParserError
    nil
  end
  private_class_method :parse_concurrency_group

  # Resolves instance_ids to display info (name, URL, type, suite ID).
  # Batch-loads all needed records to avoid N+1 queries.
  # The caller is expected to manage truncation and ordering of items before passing to this method.
  sig { params(items: T::Array[T::Hash[Symbol, T.untyped]], repository: T.untyped).returns(T::Array[BlockingItem]) }
  def self.resolve_queue_items(items, repository)
    return [] if items.empty?

    parsed_items = parse_queue_items(items)

    ext_ids = parsed_items.filter_map { |i| i[:ext_id] }.uniq
    suites = repository.actions_check_suites
      .includes(workflow_run: :latest_workflow_run_execution)
      .where(external_id: ext_ids)
      .index_by(&:external_id)

    id_paths = parsed_items.filter_map { |i| i[:id_path] }.compact.uniq
    wjr_lookup, reusable_caller_lookup = build_wjr_lookups(
      repository: repository,
      suites: suites,
      parsed_items: parsed_items,
      id_paths: id_paths,
    )

    parsed_items.filter_map do |entry|
      resolve_parsed_queue_item(entry, suites, wjr_lookup, reusable_caller_lookup)
    end
  end

  def self.parse_queue_items(items)
    items.map do |item|
      ext_id, id_path = parse_instance_id(item[:instance_id])
      { item: item, ext_id: ext_id, id_path: id_path }
    end
  end

  # Batch-load WorkflowJobRuns and precompute reusable-workflow caller resolution.
  # Returns [wjr_lookup, reusable_caller_lookup], both keyed by [execution_id, path].
  def self.build_wjr_lookups(repository:, suites:, parsed_items:, id_paths:)
    wjr_lookup = {}
    reusable_caller_lookup = {}
    return [wjr_lookup, reusable_caller_lookup] if id_paths.empty?

    workflow_run_ids = suites.values.filter_map { |s| s.workflow_run&.id }.uniq
    execution_ids = suites.values.filter_map { |s| s.workflow_run&.latest_workflow_run_execution_id }.uniq

    base_scope = Actions::WorkflowJobRun
      .includes(:check_run)
      .where(repository_id: repository.id, workflow_run_id: workflow_run_ids, workflow_run_execution_id: execution_ids)

    needed_paths_by_execution = Hash.new { |h, k| h[k] = Set.new }
    parsed_items.each do |entry|
      path = entry[:id_path]
      next if path.blank?

      suite = suites[entry[:ext_id]]
      execution_id = suite&.workflow_run&.latest_workflow_run_execution_id
      next unless execution_id

      needed_paths_by_execution[execution_id].add(path)
    end

    # First, do an exact job_key lookup (covers JobGroupLease).
    # Uses the composite index on (repository_id, workflow_run_id,
    # workflow_run_execution_id, job_key) with no LIKE predicates.
    # Covers the common case but does not match reusable workflows.
    base_scope.where(job_key: id_paths)
      .each { |wjr| wjr_lookup[[wjr.workflow_run_execution_id, wjr.job_key]] = wjr }

    # Next, prefix lookup only for [execution_id, id_path] pairs that had no
    # exact match. Reusable-workflow lease paths are only prefixes of stored
    # job_keys, but that needs to be determined per execution: the same path
    # can resolve exactly in one execution and still require prefix lookup in
    # another execution in the same batch.
    unresolved_paths_by_execution = Hash.new { |h, k| h[k] = Set.new }
    needed_paths_by_execution.each do |execution_id, paths|
      paths.each do |path|
        next if wjr_lookup.key?([execution_id, path])

        unresolved_paths_by_execution[execution_id].add(path)
      end
    end

    unresolved_paths = unresolved_paths_by_execution.values.flat_map(&:to_a).uniq
    return [wjr_lookup, reusable_caller_lookup] if unresolved_paths.empty?

    job_key_col = Actions::WorkflowJobRun.arel_table[:job_key]
    prefix_conditions = unresolved_paths
      .map do |path|
        pat = "#{ActiveRecord::Base.sanitize_sql_like(path)}.%"
        job_key_col.matches(pat)
      end
      .reduce { |cond, match| cond.or(match) }

    # Resolve reusable workflow caller jobs for the unresolved id_paths.
    reusable_state = {}
    base_scope.where(prefix_conditions)
      .each do |wjr|
        execution_id = wjr.workflow_run_execution_id
        job_key = wjr.job_key.to_s

        wjr_lookup[[execution_id, wjr.job_key]] = wjr

        needed_paths = unresolved_paths_by_execution[execution_id]
        next if needed_paths.blank?

        needed_paths.each do |path|
          next unless job_key.start_with?("#{path}.")

          reusable_key = [execution_id, path]
          # For a reusable-workflow lease, instance_id carries only the reusable
          # node path (e.g. "deploy"), while stored job_keys are descendants
          # (e.g. "deploy.build.__default" or deeper for nested reusables).
          #
          # We resolve to the nearest descendant (smallest depth delta) so the
          # blocking item refers to the immediate caller job for that reusable node.
          #
          # Example nested case:
          # - RW1 caller: "deploy.__default"
          # - RW2 caller under RW1: "deploy.build.__default"
          # - RW2 child: "deploy.build.test.__default"
          # For id_path "deploy.build", nearest caller is
          # "deploy.build.__default" (delta 1), not the deeper child (delta 2).
          candidate_depth_delta = id_path_depth(job_key) - id_path_depth(path)
          state = reusable_state[reusable_key] ||= { best_wjr: nil, best_delta: nil, ties: 0 }

          if state[:best_delta].nil? || candidate_depth_delta < state[:best_delta]
            state[:best_delta] = candidate_depth_delta
            state[:best_wjr] = wjr
            state[:ties] = 1
          elsif candidate_depth_delta == state[:best_delta]
            # Keep the first row for deterministic selection and record ties so
            # we can surface data anomalies (multiple same-depth matches).
            state[:ties] += 1
          end
        end
      end

    reusable_state.each do |(execution_id, path), state|
      reusable_caller_lookup[[execution_id, path]] = state[:best_wjr] if state[:best_wjr]
      next unless state[:ties] > 1

      # Multiple equal-depth matches are unexpected but there are no SQL constraints to prevent them.
      # Log to aid diagnosis; resolution still proceeds with the first equal-depth candidate.
      GitHub.logger.warn(
        "workflow_concurrency reusable caller resolution matched multiple same-depth jobs; " \
        "execution_id=#{execution_id} id_path=#{path} matches=#{state[:ties]}"
      )
    end

    [wjr_lookup, reusable_caller_lookup]
  end

  # Resolves a parsed queue item to a database record, considering reusable workflow caller jobs.
  # Returns a hash with information about the resolved job or workflow run.
  sig do
    params(
      entry: T::Hash[Symbol, T.untyped],
      suites: T::Hash[String, T.untyped],
      wjr_lookup: T::Hash[[Integer, String], T.untyped],
      reusable_caller_lookup: T::Hash[[Integer, String], T.untyped],
    ).returns(T.nilable(BlockingItem))
  end
  def self.resolve_parsed_queue_item(entry, suites, wjr_lookup, reusable_caller_lookup)
    item = entry[:item]
    ext_id = entry[:ext_id]
    id_path = entry[:id_path]
    suite = suites[ext_id]
    return nil unless suite

    job_run = nil
    is_reusable_workflow = false

    if id_path.present?
      execution_id = suite.workflow_run&.latest_workflow_run_execution_id
      if execution_id
        job_run = wjr_lookup[[execution_id, id_path]]

        # Reusable-workflow-level concurrency (ReusableWorkflowGroupLease):
        # The instance_id path is just the rwf_id (e.g. "build"), which doesn't
        # directly identify a job row. Resolve to the nearest caller job under
        # that reusable workflow path so the link points to the reusable call site.
        if job_run.nil?
          rw_job_run = reusable_caller_lookup[[execution_id, id_path]]
          is_reusable_workflow = true if rw_job_run
          job_run = rw_job_run
        end
      end
    end
    check_run = job_run&.check_run
    workflow_run = suite.workflow_run

    base = {
      check_suite_id: suite.id,
      check_run_id: nil,
      acquired: item[:acquired] || false,
      blocked_at_level: item[:blocked_at_level],
      workflow_run_id: workflow_run&.id,
      workflow_run_name: workflow_run&.name,
      workflow_run_run_number: workflow_run&.run_number,
      workflow_run_explicit_name: workflow_run&.explicit_name?,
      workflow_run_url: workflow_run&.permalink(include_host: false),
    }

    if is_reusable_workflow && check_run
      # The concurrency lease is on the reusable workflow as a whole, not a
      # single job. We show the matched job's full display name (e.g.
      # "build / reusable-build") and link to it so the user can navigate
      # to the actual blocking work.
      T.cast(base.merge(
        check_run_id: check_run.id,
        display_name: check_run.display_name,
        url: check_run.permalink(include_host: false),
        display_type: "reusable_workflow",
      ), BlockingItem)
    elsif check_run
      T.cast(base.merge(
        check_run_id: check_run.id,
        display_name: check_run.display_name,
        url: check_run.permalink(include_host: false),
        display_type: "job",
      ), BlockingItem)
    else
      T.cast(base.merge(
        display_name: workflow_run&.name || suite.name,
        url: suite.permalink(include_host: false),
        display_type: "run",
      ), BlockingItem)
    end
  end

  def self.id_path_depth(path)
    path.to_s.count(".") + 1
  end
  private_class_method :parse_queue_items, :build_wjr_lookups, :resolve_parsed_queue_item,
    :job_blocking_candidates, :reusable_workflow_blocking_candidates, :id_path_depth

  # Collects raw queue items (instance_id + acquired flag) ahead of the current
  # item in a concurrency group, without resolving to DB records.
  def self.queue_items_ahead(concurrency_str, repository, current_external_id, current_job_key: nil, match_by_external_id_prefix: false, run_service_client:)
    return [] unless concurrency_str.present? && repository.present? && current_external_id.present?

    concurrency_data = JSON.parse(concurrency_str) rescue nil
    group_name = concurrency_data&.dig("group")
    return [] unless group_name.present?

    result = run_service_client.get_concurrency_group(
      repository_global_id: repository.next_global_id,
      group_name: group_name
    )
    return [] unless result.call_succeeded?

    group_status = result.value

    # Build the expected instance_id for the current item
    current_ext_str = current_external_id.to_s
    expected_instance_id = current_job_key.present? ? "#{current_ext_str}.#{current_job_key}" : current_ext_str

    # Find the current item in the waiting list.
    # Workflow-level concurrency uses an exact external_id match, while the
    # workflow run page can opt into prefix matching to find any waiting job in
    # the current run for a shared job-level concurrency group.
    current = group_status.waiting_instances.find do |instance|
      next unless instance.instance_id.present?

      if match_by_external_id_prefix
        parse_instance_id(instance.instance_id).first == current_ext_str
      else
        instance.instance_id == expected_instance_id
      end
    end
    return [] unless current

    # Collect items ahead: acquired instance + waiting instances with lower position
    items_ahead = []

    if group_status.acquired_instance&.instance_id.present? &&
       group_status.acquired_instance.instance_id != current.instance_id
      items_ahead << { instance_id: group_status.acquired_instance.instance_id, acquired: true }
    end

    group_status.waiting_instances
      .select { |i| i.position < current.position && i.instance_id.present? && i.instance_id != current.instance_id }
      .sort_by(&:position)
      .each { |i| items_ahead << { instance_id: i.instance_id } }

    items_ahead
  rescue => e
    GitHub.dogstats.increment("actions.workflow_concurrency.queue_items_ahead.error", tags: ["error:#{e.class.name&.underscore}"])
    []
  end
  private_class_method :queue_items_ahead

  def blocking_resources(concurrency, owner)
    return [] unless concurrency.present?

    concurrency_json = JSON.parse(concurrency)
    waiting_on_resource = concurrency_json["waiting_on_resource"]
    blocking_check_suite = nil
    blocking_check_run = nil
    return [] unless waiting_on_resource.present?

    if waiting_on_resource["check_run_id"].present?
      blocking_check_run = Checks.domain.check_runs.unsafe_for_id(waiting_on_resource["check_run_id"].to_i)
      return unless blocking_check_run.present?
      [{
        display_name: blocking_check_run.display_name,
        url:  blocking_check_run.permalink,
        display_type: "job"
      }]
    elsif waiting_on_resource["check_suite_id"].present?
      blocking_check_suite = CheckSuite.find_by(id: waiting_on_resource["check_suite_id"].to_i)
      return unless blocking_check_suite.present?
      return [{
        display_name: blocking_check_suite.name,
        url:  blocking_check_suite.permalink,
        display_type: "run"
      }] unless waiting_on_resource["identifier"].present?

      # if identifier is present, fetch the jobs that are part of this reference workflow
      # jobs stores `parent_job_id` with format <identifier>.<jobId>
      blocking_jobs = blocking_check_suite.workflow_run&.latest_workflow_job_runs&.where("parent_job_id LIKE ?", "#{waiting_on_resource["identifier"]}.%")
      blocking_jobs.filter_map do |job|
        {
          display_name: job.check_run&.display_name,
          url:  job.check_run.permalink,
          display_type: "job"
        } if job.check_run&.status != "completed"
      end
    else
      []
    end
  end
end
