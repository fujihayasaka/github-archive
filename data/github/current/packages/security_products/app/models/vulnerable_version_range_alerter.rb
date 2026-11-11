# typed: true
# frozen_string_literal: true

# see tests for VulnerableVersionRangeCreateVulnerabilityAlerts
class VulnerableVersionRangeAlerter
  DATADOG_PREFIX = "vulnerable_version_range_alerter"
  EVENT_HYDRO_SCHEMA = "dependabot.v0.VulnerableDependencyFound"

  include GitHub::DatadogHelper
  include GitHub::Memoizer

  sig { returns(VulnerableVersionRangeAlertingProcess) }
  attr_accessor :process

  sig { returns(VulnerabilityAlertingEvent) }
  attr_accessor :event

  sig { returns(VulnerableVersionRange) }
  attr_accessor :range

  sig { returns(T.nilable(String)) }
  attr_accessor :cursor

  sig { returns(DependencyGraph::AllRepositoriesWithVersionRangeQueryInterface) }
  attr_accessor :query

  DEFAULT_BATCH_SIZE = 100
  DEFAULT_PREFILTER_BATCH_SIZE = 100
  # Maximum repo IDs to check for alertability in a single window. Uses the
  # with_vulnerability_alerts_enabled scope limit minus one for safety margin.
  PREFILTER_WINDOW_SIZE = Configurable::RepositoryVulnerabilityAlerts::WHERE_ID_LIMIT - 1
  # Cap on stashed "remaining alertable" IDs we'll serialize into the cursor.
  # The cursor is persisted in `progress_token` (MySQL TEXT, 64KB) and passed
  # as a job arg. At ~10 bytes/ID in JSON, 3000 IDs ≈ 30KB, leaving room for
  # `ri` (up to `prefilter_batch_size`), the DG-API cursor `da`, and overhead.
  # When `ra` would overflow, we truncate it and rewind the repo cursor so the
  # dropped tail is re-scanned on the next iteration (idempotent — alert
  # creation is keyed on (repo, vulnerability)).
  PREFILTER_RA_LIMIT = 3_000

  # Cap on prefilter window queries per iteration. The refill loop keeps
  # pulling windows until either the batch is full or this cap is hit, so
  # sparse regions of repo_id space (where alertable density is ~1%) don't
  # send tiny batches to DG-API. Each refill is ~2 cross-cluster queries
  # (~300ms wall time), so 10 refills caps the per-iteration prefilter
  # overhead at ~3s — safely below the 15s DG-API budget.
  MAX_PREFILTER_REFILL_ITERATIONS = 10

  sig do
    params(
      process: VulnerableVersionRangeAlertingProcess,
      cursor: T.nilable(String),
      batch_size: Integer,
      prefilter_batch_size: Integer,
    ).void
  end
  def initialize(process, cursor: nil, batch_size: DEFAULT_BATCH_SIZE, prefilter_batch_size: DEFAULT_PREFILTER_BATCH_SIZE)
    @process = process
    @event = T.let(T.must(process.vulnerability_alerting_event), VulnerabilityAlertingEvent)
    @range = T.let(T.must(process.vulnerable_version_range), VulnerableVersionRange)
    # NOTE: `sanitize_cursor` may emit a Datadog metric whose tags depend on
    # `@process`, and checks the prefilter feature flag against `range.vulnerability`.
    # Keep this assignment after `@process` and `@range` are set above.
    @cursor = sanitize_cursor(cursor)
    @batch_size = batch_size
    @prefilter_batch_size = prefilter_batch_size
    @prefilter_has_more = T.let(nil, T.nilable(T::Boolean))
    @prefilter_repo_cursor = T.let(nil, T.nilable(Integer))
    @prefilter_dg_after = T.let(nil, T.nilable(String))
    @prefilter_remaining_alertable = T.let([], T::Array[Integer])
    @query = fetch_dependents_from_range_query(process, range)
  end

  # returns alertable_dependents so they can be counted in
  # VulnVersionRange#increment_total_alerts_processed_count
  sig { returns(T::Array[DependencyGraph::Alerting::AlertableDependent]) }
  def process_alertable_repos
    alertable_dependents = T.let([], T::Array[DependencyGraph::Alerting::AlertableDependent])
    datadog_time(:total_time, tags: metric_tags) do
      dependents = executed_query.alertable_dependents
      alertable_dependents =
        datadog_time(:filter_time) do
          filter_unalertable_repos(dependents, org_id: process.org_id)
        end

      datadog_histogram(
        dependent_count: dependents.count,
        alertable_dependent_count: alertable_dependents.count,
        tags: metric_tags,
      )
      if dependents.any?
        datadog_histogram(
          alertable_percentage: 100 * alertable_dependents.count / dependents.count,
          tags: metric_tags,
        )
      end

      datadog_time(:create_time, tags: metric_tags) do
        publish_alert_creation_messages(range, alertable_dependents)
      end
    end
    alertable_dependents
  end

  sig { returns(T::Boolean) }
  def more_to_process?
    if prefilter_active?
      # Two-level check: DG-API may have more pages for the current batch,
      # or we may have more batches of alertable repos to send.
      !!executed_query.has_next? || !!@prefilter_has_more
    else
      !!executed_query.has_next? && next_cursor.present?
    end
  end

  sig { returns(T.nilable(T.any(String, T::Hash[String, T.untyped]))) }
  def next_cursor
    if prefilter_active?
      prefilter_build_cursor
    else
      executed_query.dependent_end_cursor || executed_query.last_cursor
    end
  end

  sig { returns(Integer) }
  def dependents_count
    executed_query.alertable_dependents.size
  end

  private

  # TODO: Move this method into DependencyGraph::VulnerabilityScanning
  #
  # The branching between DGP and DG-API should be moved behind a public method to isolate our domain.
  #   See: https://github.com/github/dependency-graph/pull/5751
  sig do
    params(
      process: VulnerableVersionRangeAlertingProcess,
      range: VulnerableVersionRange
    ).returns(
      DependencyGraph::AllRepositoriesWithVersionRangeQueryInterface
    )
  end
  def fetch_dependents_from_range_query(process, range)
    return dgp_fetch_dependents_from_range(range, org_id: process.org_id) if dgp_provider?

    dg_api_fetch_dependents_from_range(range, org_id: process.org_id)
  end

  sig { params(range: VulnerableVersionRange, org_id: Integer).returns(DependencyGraph::AllRepositoriesWithVersionRangeQueryInterface) }
  def dg_api_fetch_dependents_from_range(range, org_id: 0)
    # TODO: Use the AdvisoryBroadcastProcessManager to selectively disable querying DG-API for npm as part of cleanup
    #
    #   see: https://github.com/github/dependency-graph/issues/5589
    filter = {
      package_manager: range.ecosystem,
      package_name: range.affects,
      requirements: range.requirements,
      first: @batch_size,
      preview: false,
    }

    alertable_ids = prefiltered_alertable_repo_ids
    if alertable_ids
      if alertable_ids.empty?
        # No alertable repos in this batch — skip the DG-API call entirely.
        # Tag distinguishes "current window had no alertable repos, more to
        # scan" from "truly out of work" so dashboards can split them.
        reason = @prefilter_has_more ? "empty_window" : "exhausted"
        datadog_increment(:prefilter_short_circuit, tags: metric_tags + ["reason:#{reason}"])
        return DependencyGraphPlatform::AllRepositoriesWithVersionRangeQuery::NullQuery.new
      end

      # Pass pre-filtered repo IDs to DG-API so it only returns repos that are
      # both alertable AND have the vulnerability. This avoids returning results
      # we'd drop in filter_unalertable_repos (typically ~60% of results).
      # Note: repository_ids and org_id are mutually exclusive in DG-API.
      #
      # Scale `first` by the retry-backoff factor (@batch_size / DEFAULT_BATCH_SIZE)
      # so retries shrink the DG-API page size in prefilter mode too. The caller
      # job halves @batch_size on each retry (100 → 50 → 25 → 10), which in
      # legacy mode flows directly into `first`. Mirror that here.
      filter[:first] = [@prefilter_batch_size * @batch_size / DEFAULT_BATCH_SIZE, 1].max
      filter[:repository_ids] = alertable_ids
      filter[:after] = @prefilter_dg_after if @prefilter_dg_after
      datadog_increment(:prefilter_used, tags: metric_tags)
    else
      filter[:after] = cursor if cursor
      filter[:org_id] = org_id if org_id > 0
    end

    backend = DependencyGraph::Client.new(timeout: 15, query_type: "all_repositories_with_version_range")

    DependencyGraph::AllRepositoriesWithVersionRangeQuery.new(
      dependents_filter: filter,
      backend: backend,
    )
  end

  sig { params(range: VulnerableVersionRange, org_id: Integer).returns(DependencyGraph::AllRepositoriesWithVersionRangeQueryInterface) }
  def dgp_fetch_dependents_from_range(range, org_id: 0)
    manager = DependencyGraph::VulnerabilityScanning::AdvisoryBroadcastProcessManager.from_slug(
      process.detection_provider,
    )

    if manager.searchable_for?(range)
      filter = DependencyGraphPlatform::AllRepositoriesWithVersionRangeQuery::Filter.new(
        ecosystem: T.must(range.ecosystem),
        package_name: range.affects,
        requirements: range.requirements,
        org_id: org_id,
        cursor: @cursor,
      )

      DependencyGraphPlatform::AllRepositoriesWithVersionRangeQuery.new(filter: filter, limit: @batch_size)
    else
      # If DGP is disabled, return a null object which acts as an empty result set.
      DependencyGraphPlatform::AllRepositoriesWithVersionRangeQuery::NullQuery.new
    end
  end

  memoize def executed_query
    datadog_time(:query_time, tags: metric_tags) do
      query.execute_query! # Executes the query and memoizes the result
    end

    query
  end

  # Not every dependent is reportable. Filter out dependents with
  # repos that have been archived or do not have alerts turned on.
  sig { params(dependents: T::Array[DependencyGraph::Dependent], org_id: Integer).returns(T::Array[DependencyGraph::Alerting::AlertableDependent]) }
  def filter_unalertable_repos(dependents, org_id: 0)
    # Filter out dependents with missing manifest paths
    dependents = dependents.select { |dep| dep.manifest_path.present? }

    grouped_dependents = dependents.group_by(&:repository_id)
    alertable_repo_ids = fetch_alertable_repo_ids(grouped_dependents.keys, org_id: org_id)

    T.unsafe(grouped_dependents).values_at(*alertable_repo_ids).flatten
  end

  sig do
    params(
      range: VulnerableVersionRange,
      alertable_dependents: T::Array[DependencyGraph::Alerting::AlertableDependent]
    ).void
  end
  def publish_alert_creation_messages(range, alertable_dependents)
    message_count = 0

    alertable_dependents.filter_map do |dependent|
      datadog_time(:"alert.publish_time", tags: metric_tags) do
        publish_message_to_hydro(range, dependent)
        message_count += 1
      end
    end
  ensure
    process.progress.increment_denominator(by: message_count.to_i) if message_count.to_i > 0
  end

  sig { params(range: VulnerableVersionRange, dependent: DependencyGraph::Alerting::AlertableDependent).void }
  def publish_message_to_hydro(range, dependent)
    message = {
      repository_id: dependent.repository_id,
      vulnerable_dependency: {
        vulnerable_version_range_ids: [range.id],
        manifest_path: dependent.manifest_path,
        requirements: dependent.requirements,
        scope: dependent.scope_to_hydro_enum,
        relationship: dependent.relationship_to_hydro_enum,
        dgp_dependency_id: dependent.dgp_dependency_id_to_hydro,
      },
      dependency_provider: dependency_provider_for_process,
      vulnerability_alerting_event_id: event.id,
      vulnerable_version_range_alerting_process_id: process.id,
      created_at: Time.current
    }
    GitHub.hydro_publisher.publish(message, schema: EVENT_HYDRO_SCHEMA, partition_key: dependent.repository_id)
  end

  sig { returns(Symbol) }
  memoize def dependency_provider_for_process
    dg_manager = DependencyGraph::VulnerabilityScanning::AdvisoryBroadcastProcessManager.from_slug(
      process.detection_provider
    )

    dg_manager.provider.hydro_enum
  end

  sig { params(repo_ids: T::Array[Integer], org_id: Integer).returns(T::Set[Integer]) }
  def fetch_alertable_repo_ids(repo_ids, org_id: 0)
    scope = Repository.where(id: repo_ids)

    # Ensure we only include repos belonging to the organization owning the advisory
    scope = scope.where(owner_id: org_id) if org_id > 0

    T.unsafe(scope).with_vulnerability_alerts_enabled.ids.to_set
  end

  # Pre-fetches alertable repository IDs to pass to DG-API, so DG-API only
  # returns repos that are both alertable AND have the vulnerability. This avoids
  # returning results we'd drop in filter_unalertable_repos (~60% of results).
  #
  # Outer walk: cursor-walks `repository_security_settings` for rows with
  # `feature=dependency_graph, state=enabled`. DG enablement is the binding
  # prerequisite for any alert (no parsed manifest = no possible vuln match), so
  # this selective table is the smallest possible candidate universe — every
  # repo not in it is provably non-alertable. The PK `(repository_id, feature)`
  # supports a forward range scan ordered by `repository_id`.
  #
  # Each window is then narrowed to alerts-enabled repos via
  # `with_vulnerability_alerts_enabled` (a cross-cluster query on `repositories`).
  # When a window yields fewer alertable IDs than the DG-API batch size, the
  # refill loop pulls additional windows until the batch is full or
  # MAX_PREFILTER_REFILL_ITERATIONS is hit, so sparse regions don't ship tiny
  # DG-API batches.
  #
  # Cursor fields:
  # - rc: last DG-enabled repository_id processed (window high-water mark)
  # - ra: alertable IDs collected past the current batch, to drain before the
  #       next window scan
  # - ri: in-flight batch of repo IDs sent to DG-API (for DG-API pagination)
  # - da: DG-API pagination cursor within the current ri batch
  #
  # Returns nil when pre-filtering is not applicable (flag disabled, innersource
  # advisory, enterprise). Returns an empty array when no more alertable repos
  # exist.
  sig { returns(T.nilable(T::Array[Integer])) }
  memoize def prefiltered_alertable_repo_ids
    # DGP-provider processes use the DGP codepath entirely and must not touch
    # any of the DG-API prefilter logic gated behind the feature flag.
    return nil if dgp_provider?
    # Don't use for innersource advisories (org_id > 0 is an unreleased feature)
    return nil if process.org_id > 0
    # Dotcom-only: the prefilter walks `repository_security_settings` for
    # `dependency_graph: enabled` rows. On enterprise, dependency-graph
    # enablement is a global instance setting (`SecurityProduct::DependencyGraph#enabled?`
    # short-circuits with `return true if GitHub.enterprise?`), so those per-repo
    # rows aren't populated and every window resolves to empty — we'd silently
    # drop alerts. Fall back to the original DG-API path there instead.
    return nil if GitHub.enterprise?
    # Actor-scoped: enable per-vulnerability so this optimization only kicks in
    # for specific advisories (typically popular ones where the DG-API call
    # doesn't fit in our 15s timeout).
    return nil unless FeatureFlag.vexi.enabled?(:dependabot_advisory_alerting_prefilter_repo_ids, range.vulnerability, default: false)

    pf_state = parse_prefilter_cursor

    # If the flag was enabled mid-process, there may already be a non-prefilter
    # DG-API cursor in flight. Let that pagination drain via the original code
    # path; the prefilter optimization kicks in on the next fresh run. Without
    # this, the leftover cursor would be silently dropped and we'd restart from
    # the beginning, wasting work (alerts are still correct, just duplicated).
    if pf_state.nil? && cursor.present?
      datadog_increment(:prefilter_deferred_inflight_cursor, tags: metric_tags)
      return nil
    end

    if pf_state && pf_state["ri"]&.any?
      # Resuming DG-API pagination within a batch — reuse the same repo IDs
      @prefilter_dg_after = pf_state["da"]
      @prefilter_repo_cursor = pf_state["rc"]
      @prefilter_remaining_alertable = T.cast(pf_state["ra"], T.nilable(T::Array[Integer])) || []
      @prefilter_has_more = true
      return pf_state["ri"]
    end

    if pf_state && pf_state["ra"]&.any?
      # Consume previously-stashed alertable IDs from the same window before
      # spending another MySQL query on a fresh window scan.
      remaining = T.cast(pf_state["ra"], T::Array[Integer])
      batch = remaining.first(@prefilter_batch_size)
      @prefilter_remaining_alertable = remaining.drop(@prefilter_batch_size)
      @prefilter_repo_cursor = pf_state["rc"]
      @prefilter_dg_after = nil
      # Conservatively assume there's more to scan past the current window.
      # If we're wrong, the next iteration's empty window scan will correct it
      # via the `repo_ids.empty?` short-circuit below.
      @prefilter_has_more = true
      datadog_increment(:prefilter_resumed_from_ra, tags: metric_tags)
      return batch
    end

    # Fetch new batches of alertable repo IDs until the prefilter batch is full
    # or we hit the refill cap. In dense regions one window fills the batch in
    # a single iteration; in sparser regions we keep refilling to amortize the
    # DG-API call over a full batch instead of shipping tiny ones.
    repo_cursor = pf_state ? pf_state["rc"].to_i : 0

    collected = T.let([], T::Array[Integer])
    refill_iterations = 0
    truly_exhausted = T.let(false, T::Boolean)

    while collected.size < @prefilter_batch_size && refill_iterations < MAX_PREFILTER_REFILL_ITERATIONS
      repo_ids = fetch_prefilter_repo_ids(repo_cursor)

      if repo_ids.empty?
        truly_exhausted = true
        break
      end

      refill_iterations += 1
      repo_cursor = T.must(repo_ids.last)

      collected.concat(alertable_ids_for_window(repo_ids))
    end

    if refill_iterations > 1
      datadog_histogram(prefilter_refill_iterations: refill_iterations, tags: metric_tags)
    end

    @prefilter_dg_after = nil
    @prefilter_repo_cursor = repo_cursor

    if collected.empty?
      @prefilter_has_more = !truly_exhausted
      return []
    end

    batch = collected.first(@prefilter_batch_size)
    @prefilter_remaining_alertable = collected.drop(@prefilter_batch_size)

    # has_more is true unless we've drained the DG-enabled table end-to-end with
    # no leftovers. Truncation cases (refill cap, full batch) leave more data
    # behind the current cursor and require a follow-up iteration.
    @prefilter_has_more = @prefilter_remaining_alertable.any? || !truly_exhausted

    batch
  rescue Configurable::RepositoryVulnerabilityAlerts::ScopeTooBroadError
    datadog_increment(:prefilter_skipped_scope_too_broad, tags: metric_tags)
    nil
  end

  # Resolves a window of DG-enabled candidate repository IDs down to the
  # alertable subset (alerts-enabled per `with_vulnerability_alerts_enabled`).
  # Returns IDs ordered by `repositories.id`. No DG intersection is needed
  # because the source table already guarantees DG-enabled.
  sig { params(repo_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def alertable_ids_for_window(repo_ids)
    T.cast(
      Repository.where(id: repo_ids).with_vulnerability_alerts_enabled.order(:id).pluck(:id),
      T::Array[Integer],
    )
  end

  # Returns up to PREFILTER_WINDOW_SIZE repository IDs to consider next,
  # ordered by `repositories.id`. Cursor-walks `repository_security_settings`
  # for `feature=dependency_graph, state=enabled` rows — the binding
  # prerequisite for any alert. Driving the scan off this selective table
  # (rather than a full PK scan over `repositories` or a status table that
  # needs filtering) keeps every window dense with real candidates and lets the
  # PK `(repository_id, feature)` satisfy the forward range scan cleanly.
  sig { params(repo_cursor: Integer).returns(T::Array[Integer]) }
  def fetch_prefilter_repo_ids(repo_cursor)
    datadog_time(:prefilter_window_fetch_time, tags: metric_tags) do
      SecurityProductsEnablement::RepositorySecuritySetting
        .where(feature: :dependency_graph, state: :enabled)
        .where("repository_id > ?", repo_cursor)
        .order(:repository_id)
        .limit(PREFILTER_WINDOW_SIZE)
        .pluck(:repository_id)
    end
  end

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def parse_prefilter_cursor
    return nil unless cursor&.start_with?("{")
    parsed = JSON.parse(T.must(cursor))
    return nil unless parsed.is_a?(Hash) && parsed["pf"]
    parsed
  rescue JSON::ParserError
    nil
  end

  # If a prefilter cursor was persisted but the feature flag is now disabled
  # (e.g. it was toggled off after a failure), discard it and restart from the
  # beginning. Alert creation is keyed by (repo, vulnerability) and is
  # idempotent, so re-processing is safe — it just repeats work for repos
  # already alerted in this run.
  #
  # Cursors carrying a "ph" field hold an "rc" value that is not a
  # `repository_security_settings.repository_id` and would silently skip work
  # in the current walk, so we reset those too.
  #
  # Only prefilter cursors (those carrying a "pf" marker) are reset. DGP also
  # uses JSON-shaped cursors, which must be passed through untouched.
  sig { params(cursor: T.nilable(String)).returns(T.nilable(String)) }
  def sanitize_cursor(cursor)
    return cursor if dgp_provider?
    return cursor unless cursor&.start_with?("{")

    parsed = JSON.parse(T.must(cursor))
    return cursor unless parsed.is_a?(Hash) && parsed["pf"]

    flag_enabled = FeatureFlag.vexi.enabled?(:dependabot_advisory_alerting_prefilter_repo_ids, range.vulnerability, default: false)
    has_stale_ph = parsed.key?("ph")

    return cursor if flag_enabled && !has_stale_ph

    reset_reason = flag_enabled ? "cursor carries unsupported ph field" : "feature flag is disabled"
    datadog_increment(:prefilter_cursor_reset, tags: metric_tags)
    GitHub.logger.info("discarding prefilter cursor; #{reset_reason}", {
      "code.namespace": self.class.name,
      "gh.security_alerts.vulnerable_version_range_alerting_process.id": process.id,
    })
    nil
  rescue JSON::ParserError
    cursor
  end

  sig { returns(T::Boolean) }
  def dgp_provider?
    process.detection_provider == "DGP"
  end

  sig { returns(T::Boolean) }
  def prefilter_active?
    !@prefilter_has_more.nil?
  end

  # Builds a structured cursor for prefilter mode. Encodes both the repo-window
  # position and any DG-API pagination state within the current batch.
  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def prefilter_build_cursor
    rc = cap_remaining_alertable!
    ra = @prefilter_remaining_alertable
    if executed_query.has_next?
      # DG-API has more pages for the current batch of repo IDs
      dg_after = executed_query.dependent_end_cursor || executed_query.last_cursor
      c = T.let({ "pf" => true, "rc" => rc, "ri" => prefiltered_alertable_repo_ids, "da" => dg_after }, T::Hash[String, T.untyped])
      c["ra"] = ra if ra.any?
      c
    elsif @prefilter_has_more
      # Current batch exhausted, advance to the next batch of alertable repos
      c = T.let({ "pf" => true, "rc" => rc }, T::Hash[String, T.untyped])
      c["ra"] = ra if ra.any?
      c
    end
  end

  # Truncates `@prefilter_remaining_alertable` in place when it would overflow
  # the cursor size budget (PREFILTER_RA_LIMIT). When truncation happens, also
  # rewinds `@prefilter_repo_cursor` to the last kept alertable ID so the next
  # iteration's window scan re-includes the dropped tail. Mutating both keeps
  # repeated `next_cursor` calls idempotent — without the cursor mutation, a
  # second call would see `ra.size <= limit` and return the un-rewound rc.
  # Safe because alert creation is idempotent on (repo, vulnerability).
  sig { returns(T.nilable(Integer)) }
  def cap_remaining_alertable!
    ra = @prefilter_remaining_alertable
    return @prefilter_repo_cursor if ra.size <= PREFILTER_RA_LIMIT

    datadog_increment(:prefilter_ra_overflow, tags: metric_tags)
    @prefilter_remaining_alertable = T.must(ra.first(PREFILTER_RA_LIMIT))
    @prefilter_repo_cursor = T.must(@prefilter_remaining_alertable.last)
  end

  sig { returns(T::Array[String]) }
  def metric_tags
    [
      "detection_provider:#{process.detection_provider&.downcase || "unknown"}",
    ]
  end
end
