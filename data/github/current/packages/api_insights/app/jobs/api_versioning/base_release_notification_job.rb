# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Abstract base class for release-day API version notification jobs.
  #
  # Holds the shared mechanics — cursor-based batching, dry-run handling,
  # transient-Kusto retries, throttling, heartbeats, target-mode dispatch,
  # estimate-overrun backstop, per-row tenant context — and exposes a small
  # set of cohort-specific hooks that subclasses must implement (see
  # "Required hooks" below). Today only `UserReleaseNotificationJob`
  # subclasses; future cohorts (org/business) can be added without changing
  # the base.
  #
  # == Two execution modes (dispatched from #perform)
  #
  # 1. Batch mode (default) — paginates through every API caller in the
  #    user materialized view using cursor-based batching
  #    (offset_entity_id) and chains itself across pages. The MV is no
  #    longer grouped by API version, so the cohort is "every actor that
  #    has called the REST API"; per-version dedupe lives in the
  #    per-user ActionRestraint cell below. Used by the release-day
  #    `ReleaseNotificationDispatcherJob`.
  #
  # 2. Target mode (target_actor_id set) — processes exactly one actor and
  #    exits. Used for operator-targeted re-sends. Mutually exclusive with
  #    cursor-paging (offset_entity_id must be 0).
  #
  # == Deduplication
  #
  # Per-user dedupe lives in `GitHub::ActionRestraint` and is keyed by
  # `(version: latest_version, user_id: actor_id)` at the interval the
  # subclass declares (48h for users — see
  # `UserReleaseNotificationJob::PER_USER_DEDUPE_INTERVAL` for the
  # sizing rationale). Dispatcher-level dedupe is handled in
  # `ReleaseNotificationDispatcherJob`. There are no cross-batch Redis
  # keys: the per-user ActionRestraint cell is sufficient to keep
  # retries / replays / operator-targeted runs from double-sending.
  #
  # == Per-invocation instance contract
  #
  # Each ActiveJob invocation through `perform_later` or `perform_now`
  # instantiates a fresh job object and processes exactly one batch page
  # (or one target row). Anything stored on `self` — instance variables,
  # memos — is scoped to a single invocation; there is no cross-page state.
  #
  # == Required hooks
  #
  # Subclasses must implement:
  #
  #   cohort                                            — cohort tag string ("user")
  #   cohort_feature_flag                               — per-cohort kill-switch flag name
  #   fetch_rows(latest_version, offset:, batch_size:)  — Kusto page fetch
  #   fetch_count(latest_version)                       — Kusto cohort total
  #   fetch_for_actor(latest_version, actor_id:)        — Kusto single-actor fetch (target mode)
  #   hydrate_actors(actor_ids)                         — bulk AR lookup → { id => actor }
  #   find_actor(actor_id)                              — single AR lookup (target mode)
  #   actor_suspended?(actor)                           — per-cohort suspension predicate
  #   action_restraint_admit?(row, latest_version:)     — ActionRestraint dedup gate
  #   deliver_mail(actor, row, latest_version:, deprecating_versions:) — build + .deliver_later
  class BaseReleaseNotificationJob < ApplicationJob
    extend T::Helpers

    abstract!

    BATCH_SIZE = T.let(1000, Integer)
    HEARTBEAT_INTERVAL_SECONDS = T.let(30.0, Float)

    # How many sent emails to enqueue between throttle checks. The
    # throttling logic compares the actual elapsed time of the row loop
    # against the ideal elapsed time implied by `email_enqueue_rate_limit`
    # and sleeps to make up the gap. Checking on every row would burn CPU
    # on `clock_gettime` for no benefit; checking too rarely would let the
    # per-batch send rate spike well above the target before the first
    # sleep lands. 50 sits in the middle.
    THROTTLE_CHECK_INTERVAL = T.let(50, Integer)

    TRANSIENT_KUSTO_ERRORS = T.let([
      Kusto::UnauthorizedError,
      Kusto::TooManyRequestsError,
      Kusto::InternalServerError,
      Kusto::ServiceUnavailableError,
      Kusto::GatewayTimeoutError,
    ].freeze, T::Array[T.class_of(Kusto::Error)])

    # Hard cap on how many pages past `estimated_total_pages` the chain is
    # allowed to run before forcibly terminating. Backstops the otherwise-
    # only termination signal (`has_more_pages`, derived from each Kusto
    # fetch) so a continuously-growing cohort cannot keep the chain alive
    # indefinitely. 100 gives ~2x headroom over observed dry-run drift on
    # the deprecation pipeline while bounding worst-case runaway at
    # ~100k extra deliveries (= 100 * BATCH_SIZE) per release. Re-tune
    # from the `api_versioning.estimate_overrun_pages` gauge once it has
    # release-pipeline data.
    ESTIMATE_OVERRUN_GRACE_PAGES = T.let(100, Integer)

    queue_as :mailers

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    # Total retry duration: 4 backoff gaps between 5 attempts at
    # `:polynomially_longer` (n^4 + 2 + jitter), so ~3 + 18 + 83 + 258 = 362 s
    # base (~6 min), up to ~415 s (~7 min) with 15% jitter.
    TRANSIENT_KUSTO_ERRORS.each do |error_class|
      retry_on error_class, wait: :polynomially_longer, attempts: 5
    end

    # Per-cohort email enqueue rate limit (deliver_later calls / second),
    # used by the throttling logic in `perform_batch`. The user cohort
    # sends one email per recipient (no BCC fan-out), so its limit hits
    # the ~500 outbound SMTP messages/sec cap directly. Set on each
    # subclass so the value is visible alongside the rest of the cohort's
    # tuning constants.
    sig { abstract.returns(Integer) }
    def self.email_enqueue_rate_limit; end

    sig do
      params(
        latest_version: String,
        deprecating_versions: T::Hash[String, String],
        correlation_id: String,
        offset_entity_id: Integer,
        dry_run: T::Boolean,
        batch_size: Integer,
        pages_processed: Integer,
        estimated_total_pages: Integer,
        target_actor_id: T.nilable(Integer),
      ).void
    end
    def perform(latest_version, deprecating_versions:, correlation_id:, offset_entity_id: 0, dry_run: false, batch_size: BATCH_SIZE, pages_processed: 0, estimated_total_pages: 0, target_actor_id: nil)
      # Mode dispatcher. target_actor_id and cursor-paging are mutually
      # exclusive because a target run always processes exactly one row
      # and exits — there is nothing to page through.
      if target_actor_id && offset_entity_id != 0
        raise ArgumentError, "target_actor_id and offset_entity_id are mutually exclusive"
      end

      if target_actor_id
        perform_target(
          latest_version,
          deprecating_versions: deprecating_versions,
          correlation_id: correlation_id,
          target_actor_id: target_actor_id,
          dry_run: dry_run,
        )
      else
        perform_batch(
          latest_version,
          deprecating_versions: deprecating_versions,
          correlation_id: correlation_id,
          offset_entity_id: offset_entity_id,
          dry_run: dry_run,
          batch_size: batch_size,
          pages_processed: pages_processed,
          estimated_total_pages: estimated_total_pages,
        )
      end
    end

    private

    # The current page's fetched rows. Set by perform_batch immediately
    # after the Kusto fetch, and by perform_target as `[row]`.
    sig { returns(T.nilable(T::Array[T.untyped])) }
    attr_reader :current_rows

    # Per-page id → Business map built once in perform_batch /
    # perform_target right after the Kusto fetch, and consumed per-row by
    # `with_tenant_for` below. Empty (and `with_tenant_for` short-circuits)
    # outside Proxima.
    sig { returns(T.nilable(T::Hash[Integer, Business])) }
    attr_reader :business_map

    # ------------------------------------------------------------------
    # Required cohort-specific hooks
    # ------------------------------------------------------------------

    # The cohort tag string. Emitted as the `cohort:` dogstats tag.
    sig { abstract.returns(String) }
    def cohort; end

    # The cohort-specific kill-switch feature flag name (e.g.
    # "api_versioning_release_emails_users_enabled"). Combined with
    # the global "api_versioning_release_emails_enabled" flag for the
    # mid-batch stopping check.
    sig { abstract.returns(String) }
    def cohort_feature_flag; end

    sig do
      abstract.params(
        latest_version: String,
        offset: Integer,
        batch_size: Integer,
      ).returns(T::Array[T.untyped])
    end
    def fetch_rows(latest_version, offset:, batch_size:); end

    sig { abstract.params(latest_version: String).returns(Integer) }
    def fetch_count(latest_version); end

    sig do
      abstract.params(
        latest_version: String,
        actor_id: Integer,
      ).returns(T::Array[T.untyped])
    end
    def fetch_for_actor(latest_version, actor_id:); end

    sig { abstract.params(actor_ids: T::Array[Integer]).returns(T::Hash[Integer, T.untyped]) }
    def hydrate_actors(actor_ids); end

    sig { abstract.params(actor_id: Integer).returns(T.untyped) }
    def find_actor(actor_id); end

    sig { abstract.params(actor: T.untyped).returns(T::Boolean) }
    def actor_suspended?(actor); end

    # ActionRestraint dedup gate. Returns true if the action should
    # proceed (i.e. the actor has not been notified within the dedupe
    # interval), false otherwise. The literal key string and actor kwarg
    # name are part of the persisted Redis key — keeping the whole call
    # inside the subclass (rather than a kwargs-builder hook the base
    # would splat) makes the persisted contract trivial to audit, and
    # avoids Sorbet's rejection of splatting into a method with required
    # keyword params.
    sig do
      abstract.params(
        row: T.untyped,
        latest_version: String,
      ).returns(T::Boolean)
    end
    def action_restraint_admit?(row, latest_version:); end

    # Build the cohort's mailer and call .deliver_later. The base class
    # times this call externally for `api_versioning.enqueue_duration_ms`,
    # so the subclass body is just "build the mailer + .deliver_later".
    sig do
      abstract.params(
        actor: T.untyped,
        row: T.untyped,
        latest_version: String,
        deprecating_versions: T::Hash[String, String],
      ).void
    end
    def deliver_mail(actor, row, latest_version:, deprecating_versions:); end

    # ------------------------------------------------------------------
    # Shared mechanics
    # ------------------------------------------------------------------

    sig do
      params(
        latest_version: String,
        deprecating_versions: T::Hash[String, String],
        correlation_id: String,
        offset_entity_id: Integer,
        dry_run: T::Boolean,
        batch_size: Integer,
        pages_processed: Integer,
        estimated_total_pages: Integer,
      ).void
    end
    def perform_batch(latest_version, deprecating_versions:, correlation_id:, offset_entity_id:, dry_run:, batch_size:, pages_processed:, estimated_total_pages:)
      current_page = pages_processed + 1

      # Measure the entire runtime of perform (guard checks, Kusto fetch,
      # MySQL hydration, and the enqueue loop) so
      # `api_versioning.batch_duration_ms` reflects the full batch.
      job_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)

      # First log line — emitted before any early-return branch so we can
      # always confirm the worker picked up an enqueued page.
      GitHub.logger.info(
        "perform invoked",
        "gh.cohort" => cohort,
        "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id,
        "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
        "gh.correlation_id" => correlation_id,
      )

      # Per-batch flag re-checks — evaluated on every page so disabling a
      # flag mid-run stops the pipeline at the next batch boundary rather
      # than mid-batch.
      stopping_flag = [
        "api_versioning_release_emails_enabled",
        cohort_feature_flag,
      ].find { |flag| !FeatureFlag.vexi.enabled?(flag, default: false) }
      if stopping_flag
        GitHub.logger.info(
          "stopping — #{stopping_flag} is off",
          "gh.cohort" => cohort,
          "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      # Re-read dry_run from the flag on every page so a mid-run toggle
      # takes effect, but preserve an explicit dry_run: true passed in.
      dry_run ||= FeatureFlag.vexi.enabled?("api_versioning_release_emails_dry_run", default: true)

      if offset_entity_id == 0
        total = fetch_count(latest_version)
        GitHub.dogstats.gauge("api_versioning.total_cohort_size", total, tags: cohort_tags(latest_version))
        # Compute estimated_total_pages once on page 1 from the cohort
        # count snapshot, then thread it through perform_later so
        # subsequent batches can log progress without re-querying. This
        # is an *estimate*, not a bound — termination is driven by
        # `has_more_pages` (recomputed every page).
        estimated_total_pages = (total.to_f / batch_size).ceil
      end

      GitHub.logger.info(
        "starting batch",
        "gh.cohort" => cohort,
        "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id, "gh.current_page" => current_page,
        "gh.estimated_total_pages" => estimated_total_pages, "gh.dry_run" => dry_run,
        "gh.correlation_id" => correlation_id,
      )

      # Fetch one extra row beyond batch_size so we can tell, in this
      # same call, whether a next page exists. Avoids the otherwise-
      # required "enqueue, fetch zero, stop" round-trip when the cohort
      # total is an exact multiple of batch_size.
      kusto_fetch_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      rows = fetch_rows(latest_version, offset: offset_entity_id, batch_size: batch_size + 1)
      GitHub.dogstats.timing(
        "api_versioning.kusto_fetch_duration_ms",
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - kusto_fetch_start) * 1000).round,
        tags: cohort_tags(latest_version),
      )
      has_more_pages = rows.size > batch_size
      # Discard the peeked-at extra row so it isn't processed twice: the
      # next page will re-fetch it via `where actor_id > offset_id`.
      rows = rows.first(batch_size)

      if rows.empty?
        emit_estimate_overrun_metric(current_page: current_page, estimated_total_pages: estimated_total_pages, latest_version: latest_version)
        GitHub.logger.info(
          "empty page — stopping",
          "gh.cohort" => cohort,
          "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.completed" => true,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      @current_rows = T.let(rows, T.nilable(T::Array[T.untyped]))
      @business_map = T.let(build_business_map(rows), T.nilable(T::Hash[Integer, Business]))

      GitHub.logger.info(
        "fetched rows",
        "gh.cohort" => cohort,
        "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id, "gh.row_count" => rows.size,
        "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
        "gh.correlation_id" => correlation_id,
      )

      GitHub.dogstats.count("api_versioning.rows_fetched", rows.size, tags: cohort_tags(latest_version))

      mysql_hydration_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      actor_map = hydrate_actors(rows.map(&:actor_id))
      GitHub.dogstats.timing(
        "api_versioning.mysql_hydration_duration_ms",
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - mysql_hydration_start) * 1000).round,
        tags: cohort_tags(latest_version),
      )

      emails_sent = 0
      emails_skipped = 0
      not_found_count = 0
      suspended_count = 0
      dry_run_count = 0

      # Captured immediately before the row loop so the rate calculation
      # reflects only the time spent enqueueing emails — not the upstream
      # I/O — and matches the "deliver_later/sec" units of
      # `email_enqueue_rate_limit`.
      enqueue_loop_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      throttle_total = T.let(0.0, Float)
      rate_limit = self.class.email_enqueue_rate_limit

      last_heartbeat_at = T.let(T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float), Float)

      rows.each_with_index do |row, index|
        row_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)

        outcome = process_row(
          row,
          actor_map: actor_map,
          latest_version: latest_version,
          deprecating_versions: deprecating_versions,
          dry_run: dry_run,
        )

        case outcome
        when :sent      then emails_sent += 1
        when :skipped   then emails_skipped += 1
        when :not_found then not_found_count += 1
        when :suspended then suspended_count += 1
        when :dry_run   then dry_run_count += 1
        end

        # Throttle the enqueue loop so we stay below `rate_limit`
        # deliver_later calls per second. Only `:sent` outcomes produce
        # SMTP traffic, so only they count against the budget.
        if outcome == :sent && rate_limit > 0 && emails_sent % THROTTLE_CHECK_INTERVAL == 0
          elapsed = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float) - enqueue_loop_start
          target_elapsed = emails_sent.to_f / rate_limit
          if target_elapsed > elapsed
            delay = target_elapsed - elapsed
            sleep(delay)
            throttle_total += delay
          end
        end

        # Emit per-row enqueue latency only for real sends; the metric is
        # meaningless for skip/not_found/suspended/dry_run paths.
        if outcome == :sent
          GitHub.dogstats.timing(
            "api_versioning.enqueue_duration_ms",
            ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - row_start) * 1000).round,
            tags: cohort_tags(latest_version),
          )
        end

        now = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
        if now - last_heartbeat_at >= HEARTBEAT_INTERVAL_SECONDS
          processed_in_batch = index + 1
          GitHub.logger.info(
            "heartbeat — still processing batch",
            "gh.cohort" => cohort,
            "gh.latest_version" => latest_version,
            "gh.offset" => offset_entity_id,
            "gh.current_page" => current_page,
            "gh.estimated_total_pages" => estimated_total_pages,
            "gh.processed_in_batch" => processed_in_batch,
            "gh.batch_size" => rows.size,
            "gh.sent_so_far" => emails_sent,
            "gh.skipped_so_far" => emails_skipped,
            "gh.dry_run_so_far" => dry_run_count,
            "gh.not_found_so_far" => not_found_count,
            "gh.suspended_so_far" => suspended_count,
            "gh.correlation_id" => correlation_id,
          )
          last_heartbeat_at = now
        end
      end

      tags = cohort_tags(latest_version)
      GitHub.dogstats.timing("api_versioning.batch_duration_ms", ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - job_start) * 1000).round, tags: tags)
      GitHub.dogstats.count("api_versioning.sent", emails_sent, tags: tags)
      GitHub.dogstats.count("api_versioning.skipped", emails_skipped, tags: tags)
      GitHub.dogstats.count("api_versioning.skipped_not_found", not_found_count, tags: tags)
      GitHub.dogstats.count("api_versioning.skipped_suspended", suspended_count, tags: tags)
      GitHub.dogstats.count("api_versioning.dry_run", dry_run_count, tags: tags)
      GitHub.dogstats.timing("api_versioning.throttle_sleep_ms", (throttle_total * 1000).round, tags: tags)

      GitHub.logger.info(
        "batch complete",
        "gh.cohort" => cohort,
        "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id,
        "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages, "gh.has_more_pages" => has_more_pages,
        "gh.sent" => emails_sent, "gh.skipped" => emails_skipped, "gh.dry_run_count" => dry_run_count,
        "gh.not_found" => not_found_count, "gh.suspended" => suspended_count,
        "gh.throttle_sleep_ms" => (throttle_total * 1000).round,
        "gh.correlation_id" => correlation_id,
      )

      if has_more_pages
        # Backstop the per-page `has_more_pages` termination signal so a
        # continuously-growing cohort cannot keep the chain alive forever.
        cap = estimated_total_pages + ESTIMATE_OVERRUN_GRACE_PAGES
        if estimated_total_pages > 0 && current_page >= cap
          overrun_pages = current_page - estimated_total_pages
          GitHub.dogstats.count("api_versioning.estimate_overrun_cap_hit", 1, tags: cohort_tags(latest_version))
          emit_estimate_overrun_metric(current_page: current_page, estimated_total_pages: estimated_total_pages, latest_version: latest_version)
          GitHub.logger.warn(
            "estimate overrun cap hit — stopping chain",
            "gh.cohort" => cohort,
            "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id,
            "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
            "gh.cap" => cap, "gh.overrun_pages" => overrun_pages,
            "gh.completed" => true,
            "gh.correlation_id" => correlation_id,
          )
          return
        end

        next_offset = rows.last.actor_id
        GitHub.logger.info(
          "enqueueing next page",
          "gh.cohort" => cohort,
          "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.next_page" => current_page + 1, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.next_offset" => next_offset, "gh.correlation_id" => correlation_id,
        )
        self.class.perform_later(
          latest_version,
          deprecating_versions: deprecating_versions,
          correlation_id: correlation_id,
          offset_entity_id: next_offset,
          dry_run: dry_run,
          batch_size: batch_size,
          pages_processed: current_page,
          estimated_total_pages: estimated_total_pages,
        )
        # Confirmation log — fires only if perform_later returned without
        # raising, so a missing line here (paired with the "enqueueing
        # next page" line above) tells us the enqueue itself raised and
        # was caught upstream.
        GitHub.logger.info(
          "enqueued next page",
          "gh.cohort" => cohort,
          "gh.latest_version" => latest_version, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.next_page" => current_page + 1, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.next_offset" => next_offset, "gh.correlation_id" => correlation_id,
        )
      else
        emit_estimate_overrun_metric(current_page: current_page, estimated_total_pages: estimated_total_pages, latest_version: latest_version)
        GitHub.logger.info(
          "final page — chain complete",
          "gh.cohort" => cohort,
          "gh.latest_version" => latest_version,
          "gh.pages_processed_total" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.completed" => true,
          "gh.correlation_id" => correlation_id,
        )
      end
    end

    sig do
      params(
        latest_version: String,
        deprecating_versions: T::Hash[String, String],
        correlation_id: String,
        target_actor_id: Integer,
        dry_run: T::Boolean,
      ).void
    end
    def perform_target(latest_version, deprecating_versions:, correlation_id:, target_actor_id:, dry_run:)
      GitHub.logger.info(
        "target run invoked",
        "gh.cohort" => cohort,
        "gh.latest_version" => latest_version,
        "gh.target_actor_id" => target_actor_id,
        "gh.correlation_id" => correlation_id,
      )

      # Same stopping-flag semantics as batch mode.
      stopping_flag = [
        "api_versioning_release_emails_enabled",
        cohort_feature_flag,
      ].find { |flag| !FeatureFlag.vexi.enabled?(flag, default: false) }
      if stopping_flag
        GitHub.logger.info(
          "target run stopping — #{stopping_flag} is off",
          "gh.cohort" => cohort,
          "gh.latest_version" => latest_version,
          "gh.target_actor_id" => target_actor_id,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      dry_run ||= FeatureFlag.vexi.enabled?("api_versioning_release_emails_dry_run", default: true)

      rows = fetch_for_actor(latest_version, actor_id: target_actor_id)

      if rows.empty?
        GitHub.logger.info(
          "target actor not found in cohort — exiting",
          "gh.cohort" => cohort,
          "gh.latest_version" => latest_version,
          "gh.target_actor_id" => target_actor_id,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      row = rows.first
      @current_rows = T.let(rows, T.nilable(T::Array[T.untyped]))
      @business_map = T.let(build_business_map(rows), T.nilable(T::Hash[Integer, Business]))
      actor = find_actor(row.actor_id)
      actor_map = T.let(actor ? { row.actor_id => actor } : {}, T::Hash[Integer, T.untyped])

      row_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      outcome = process_row(
        row,
        actor_map: actor_map,
        latest_version: latest_version,
        deprecating_versions: deprecating_versions,
        dry_run: dry_run,
      )

      if outcome == :sent
        GitHub.dogstats.timing(
          "api_versioning.enqueue_duration_ms",
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - row_start) * 1000).round,
          tags: cohort_tags(latest_version) + ["mode:target"],
        )
      end

      tags = cohort_tags(latest_version) + ["mode:target"]
      GitHub.dogstats.count("api_versioning.#{outcome_metric(outcome)}", 1, tags: tags)

      GitHub.logger.info(
        "target run complete",
        "gh.cohort" => cohort,
        "gh.latest_version" => latest_version,
        "gh.target_actor_id" => target_actor_id,
        "gh.outcome" => outcome.to_s,
        "gh.completed" => true,
        "gh.correlation_id" => correlation_id,
      )
    end

    # Shared per-row delivery logic used by both perform_batch and
    # perform_target. Returns a Symbol describing the outcome so each
    # caller can aggregate however it likes. Does NOT raise on
    # missing/suspended actors — those are normal outcomes that the
    # caller records and moves on from.
    sig do
      params(
        row: T.untyped,
        actor_map: T::Hash[Integer, T.untyped],
        latest_version: String,
        deprecating_versions: T::Hash[String, String],
        dry_run: T::Boolean,
      ).returns(Symbol)
    end
    def process_row(row, actor_map:, latest_version:, deprecating_versions:, dry_run:)
      actor = actor_map[row.actor_id]
      return :not_found unless actor
      return :suspended if actor_suspended?(actor)

      # Skip ActionRestraint during dry runs so dedup cells are not
      # written. Writing cells during a dry run would block real sends
      # on the next live run.
      unless dry_run
        unless action_restraint_admit?(row, latest_version: latest_version)
          return :skipped
        end
      end

      return :dry_run if dry_run

      # The deliver_mail call is wrapped in `with_tenant_for` so that, in
      # Proxima, GitHub::CurrentTenant is set to the row's owning Business
      # at the moment .deliver_later runs. The AJ tenant-context
      # before_enqueue hook reads the thread-local tenant and stamps
      # X-GitHub-Tenant-* headers onto the serialized MailDeliveryJob
      # payload; without this wrap, a cross-tenant batch (legal in Proxima
      # because the MV summarizes by tenant_id) would enqueue every mail
      # delivery job with no tenant header, and the worker would
      # deserialize the recipient User GID against the wrong DB and/or
      # send through the wrong tenant's mail config.
      #
      # The email body itself is intentionally generic (no tenant-specific
      # URLs), so the wrap is purely about the enqueue-time header
      # stamping — not about anything rendered inside the mailer
      # templates.
      #
      # Outside Proxima `with_tenant_for` is a no-op pass-through. Returns
      # false when the row's tenant_id couldn't be resolved (logged at
      # warn level inside the helper); we treat that as a skip rather
      # than a hard failure so the rest of the page proceeds. The
      # unresolved-tenant path also increments a dedicated
      # `skipped_unresolved_tenant` counter so the dashboard / alerting
      # can distinguish this (it should be ~0 in steady state) from the
      # generic `skipped` bucket it rolls into.
      delivered = with_tenant_for(row) do
        deliver_mail(
          actor,
          row,
          latest_version: latest_version,
          deprecating_versions: deprecating_versions,
        )
      end
      unless delivered
        GitHub.dogstats.increment(
          "api_versioning.skipped_unresolved_tenant",
          tags: cohort_tags(latest_version),
        )
        return :skipped
      end

      :sent
    end

    # Maps a #process_row outcome symbol to the matching dogstats metric
    # suffix used in target-mode reporting. Kept aligned with the batch
    # counters above so dashboards can sum across modes.
    sig { params(outcome: Symbol).returns(String) }
    def outcome_metric(outcome)
      case outcome
      when :sent      then "sent"
      when :skipped   then "skipped"
      when :not_found then "skipped_not_found"
      when :suspended then "skipped_suspended"
      when :dry_run   then "dry_run"
      else                 "unknown_outcome"
      end
    end

    sig { params(latest_version: String).returns(T::Array[String]) }
    def cohort_tags(latest_version)
      ["version:#{latest_version}", "email_type:release", "cohort:#{cohort}"]
    end

    # Resolve the tenant Business records for a page of cohort rows. Used
    # by perform_batch / perform_target right after the Kusto fetch to
    # publish `@business_map`, which `with_tenant_for` consults per-row.
    sig { params(rows: T::Array[T.untyped]).returns(T::Hash[Integer, Business]) }
    def build_business_map(rows)
      return {} unless GitHub.multi_tenant_enterprise?

      tenant_ids = rows.filter_map(&:tenant_id).uniq
      return {} if tenant_ids.empty?

      Business.where(id: tenant_ids).index_by(&:id)
    end

    # Run a block with GitHub::CurrentTenant set to the Business that
    # owns the row's tenant_id. Returns true if the block ran, false if
    # the row had to be skipped because its tenant could not be resolved.
    #
    # Outside Proxima this is a no-op pass-through (the block runs, true
    # is returned). Inside Proxima the block runs inside a
    # CurrentTenant.set frame so that the AJ tenant-context
    # before_enqueue hook, when the mailer calls `.deliver_later`,
    # stamps X-GitHub-Tenant-* headers onto the serialized
    # MailDeliveryJob payload. The worker uses those headers to
    # deserialize the recipient User GID against the correct tenant DB
    # and to send through the correct tenant's mail config. Without this
    # wrap, a cross-tenant batch (legal in Proxima because the MV
    # summarizes by tenant_id) would enqueue every deliver job with no
    # tenant header.
    #
    # This is the same pattern other cross-tenant batched mailer jobs
    # use — e.g. NotifyExpiredTrialsJob, DeleteExpiredTrialsJob,
    # ScanEmuOrganizationUsersJob — factored into a helper here because
    # the row loop is tight and we pre-resolve tenants into
    # `business_map` so the per-row lookup is O(1).
    #
    # Note: this is NOT about anything the mailer renders — the email
    # body is intentionally generic (no tenant-specific URLs). It is
    # purely about the enqueue-time tenant header on the downstream
    # MailDeliveryJob.
    #
    # `GitHub::CurrentTenant.set(business) { ... }` clears the
    # thread-local on exit; it does not restore a prior value. That is
    # safe here because this job is wrapped in
    # `GitHub::CurrentTenant.unscope` by ActiveJob::TenantContext's
    # around_perform (via `exempt_from_tenant_context_requirement` on
    # each cohort subclass), so each row enters with tenant == nil.
    sig do
      type_parameters(:T)
        .params(row: T.untyped, blk: T.proc.returns(T.type_parameter(:T)))
        .returns(T::Boolean)
    end
    def with_tenant_for(row, &blk)
      unless GitHub.multi_tenant_enterprise?
        blk.call
        return true
      end

      business = @business_map&.dig(row.tenant_id)
      if business.nil?
        GitHub.logger.warn(
          "skipping row — could not resolve tenant",
          "gh.cohort" => cohort,
          "gh.row.actor_id" => row.actor_id,
          "gh.row.tenant_id" => row.tenant_id,
        )
        return false
      end

      GitHub::CurrentTenant.set(business) { blk.call }
      true
    end

    # Emit the per-release drift between the page-zero estimate and where
    # the chain actually terminated. Floored at zero — a chain that
    # ended early reports 0 rather than a negative number.
    sig do
      params(
        current_page: Integer,
        estimated_total_pages: Integer,
        latest_version: String,
      ).void
    end
    def emit_estimate_overrun_metric(current_page:, estimated_total_pages:, latest_version:)
      overrun = [current_page - estimated_total_pages, 0].max
      GitHub.dogstats.gauge(
        "api_versioning.estimate_overrun_pages",
        overrun,
        tags: cohort_tags(latest_version),
      )
    end
  end
end
