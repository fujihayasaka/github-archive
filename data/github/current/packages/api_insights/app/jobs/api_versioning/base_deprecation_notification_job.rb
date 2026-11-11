# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Abstract base class for per-cohort API version deprecation notification jobs.
  #
  # Holds all the shared mechanics — paging, locking, dry-run handling, metrics,
  # logging, error recovery, target-mode dispatch — and exposes a small set of
  # cohort-specific hooks that subclasses must implement (see "Required hooks"
  # below). Subclasses keep their own class names so per-cohort retry telemetry
  # and Datadog dashboards remain split by class.
  #
  # == Two execution modes (dispatched from #perform)
  #
  # 1. Batch mode (default) — paginates through the full cohort using
  #    cursor-based batching (offset_entity_id) and chains itself across pages.
  #    Used by the daily DeprecationCheckJob.
  #
  # 2. Target mode (target_actor_id set) — processes exactly one actor and
  #    exits. Used for partial-failure recovery and operator-targeted re-sends.
  #    Mutually exclusive with cursor-paging (offset_entity_id must be 0).
  #
  # Both modes acquire the wave's running-key NX mutex (so a target run cannot
  # race a real wave dispatch and vice-versa) and respect dry_run + stopping
  # flags. Only batch mode writes the completed_key — a target run must not
  # suppress real wave dispatches for the rest of the cadence window.
  #
  # == Deduplication
  #
  # - Batch mode writes the running_key on the first page (offset_entity_id == 0)
  #   only. Cursor pages (offset_entity_id > 0) inherit the lock from page 0
  #   and refresh its TTL.
  # - Target mode always acquires the running_key on entry and always releases
  #   it on exit (success or failure) via ensure.
  # - On the final batch page a completed_key is written so the orchestrator
  #   skips re-enqueueing on future daily runs.
  #
  # == Per-invocation instance contract
  #
  # Each ActiveJob invocation through `perform_later` or `perform_now`
  # instantiates a fresh job object and processes exactly one batch page (or
  # one target row in target mode). Anything stored on `self` — instance
  # variables, memos, accumulators — is therefore scoped to a single
  # invocation; there is no cross-page state.
  #
  # Subclasses can rely on this to memoize batch-scoped prefetches with
  # `@foo ||= ...` against `current_rows`, which is set exactly once per
  # invocation in `perform_batch` / `perform_target` before the row loop runs.
  #
  # Note: the contract is per *invocation*, not per *instance object*. If
  # someone manually constructs a single instance and calls `perform` on it
  # twice (`job = Klass.new; job.perform(a); job.perform(b)`), memos from
  # the first call leak into the second — that pattern is non-idiomatic
  # ActiveJob usage and is explicitly out of scope for this contract.
  #
  # == Required hooks
  #
  # Subclasses must implement:
  #
  #   cohort                          — cohort tag string ("user" / "org" / "business")
  #   cohort_feature_flag             — per-cohort kill-switch flag name
  #   fetch_rows(version, offset:, batch_size:)  — Kusto page fetch
  #   fetch_count(version)            — Kusto cohort total
  #   fetch_for_actor(version, actor_id:)        — Kusto single-actor fetch (target mode)
  #   hydrate_actors(actor_ids)       — bulk AR lookup → { id => actor }
  #   find_actor(actor_id)            — single AR lookup (target mode)
  #   actor_suspended?(actor)         — per-cohort suspension predicate
  #   action_restraint_admit?(row, ...) — ActionRestraint dedup gate (cohort-specific actor kwarg)
  #   deliver_mail(actor, row, ...)   — build + .deliver_later the cohort's mailer
  #
  # Subclasses MAY override (default no-op) to add cohort-specific batch-scoped
  # prefetches; today only UserDeprecationNotificationJob does this for
  # token-name resolution.
  class BaseDeprecationNotificationJob < ApplicationJob
    extend T::Helpers

    abstract!

    # Rows per Kusto/MySQL page. 1000 matches the monolith's read-batch
    # convention. Per-row work (Resque enqueue + ActionRestraint Redis write
    # + MySQL hydration) means this also functions as a write-batch ceiling,
    # so the conventional 1000 — not a larger "read-only" size — is the
    # right value.
    #
    # Total run wall-clock is throttle-floor-dominated (500 emails/sec
    # ceiling, ~99% of rows result in a send), so batch size barely moves
    # the ~19 h projection for the user cohort. What batch size DOES set is
    # per-batch wall (~520 ms steady-state), which feeds into the
    # NotificationWave::RUNNING_TTL invariant — see the doc-block on that
    # constant for the full chain.
    BATCH_SIZE = T.let(1000, Integer)
    HEARTBEAT_INTERVAL_SECONDS = T.let(30.0, Float)

    # How many sent emails to enqueue between throttle checks. The throttling
    # logic compares the actual elapsed time of the row loop against the
    # ideal elapsed time implied by `email_enqueue_rate_limit` and sleeps to
    # make up the gap. Checking on every row would burn CPU on `clock_gettime`
    # for no benefit; checking too rarely would let the per-batch send rate
    # spike well above the target before the first sleep lands. 50 sits in
    # the middle: at the slowest configured cohort rate (70/sec) it fires
    # roughly every 0.7 s, which keeps the rolling rate within ~10 % of the
    # target without measurable overhead.
    THROTTLE_CHECK_INTERVAL = T.let(50, Integer)

    TRANSIENT_KUSTO_ERRORS = T.let([
      Kusto::UnauthorizedError,
      Kusto::TooManyRequestsError,
      Kusto::InternalServerError,
      Kusto::ServiceUnavailableError,
      Kusto::GatewayTimeoutError,
    ].freeze, T::Array[T.class_of(Kusto::Error)])

    # Hard cap on how many pages past `estimated_total_pages` the chain is
    # allowed to run before forcibly marking the wave completed. Backstops the
    # otherwise-only termination signal (`has_more_pages`, derived from each
    # Kusto fetch) so a continuously-growing cohort cannot keep the chain
    # alive indefinitely. Any actors not reached before the cap are skipped
    # for this wave; they will be picked up by the next wave for the same
    # deprecation, which `DeprecationCheckJob` dispatches once the current
    # wave's `send_cadence` (currently 30–60 days) elapses. We deliberately
    # do not re-process them sooner: with up to ~30M actors per cohort per
    # wave, re-walking the full cohort on a shorter interval would put
    # unacceptable load on Kusto and MySQL hydration.
    #
    # Sized from observed dry-run drift (May 2026): user cohort drifted 49
    # pages past its estimate, org by 1, business by 0. 100 gives ~2× headroom
    # over the worst observed case while bounding worst-case runaway at
    # ~100k extra deliveries (= 100 * BATCH_SIZE) per wave per cohort.
    # Re-tune from `api_versioning.estimate_overrun_pages` once it has data.
    ESTIMATE_OVERRUN_GRACE_PAGES = T.let(100, Integer)

    queue_as :mailers

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    # Total retry duration: 4 backoff gaps between 5 attempts at
    # `:polynomially_longer` (n^4 + 2 + jitter), so ~3 + 18 + 83 + 258 = 362 s
    # base (~6 min), up to ~415 s (~7 min) with 15% jitter — well under
    # NotificationWave::RUNNING_TTL, so the retry chain cannot expire the
    # running-key lock by itself.
    TRANSIENT_KUSTO_ERRORS.each do |error_class|
      retry_on error_class, wait: :polynomially_longer, attempts: 5
    end

    # Subclass registry consumed by DeprecationCheckJob to fan out per-cohort
    # dispatches. Listed explicitly (rather than via descendants reflection) so
    # that adding a new cohort is a single, reviewable diff in this file. New
    # cohorts must also implement the `cohort_identifier` and
    # `cohort_feature_flag_name` class methods below.
    sig { returns(T::Array[T.class_of(BaseDeprecationNotificationJob)]) }
    def self.cohort_jobs
      [
        UserDeprecationNotificationJob,
      ]
    end

    # Class-level cohort tag accessor consumed by DeprecationCheckJob. Mirrors
    # the per-instance `cohort` hook below — split out as a class method
    # because Sorbet rejects `job_class::COHORT` dynamic constant lookups.
    sig { abstract.returns(String) }
    def self.cohort_identifier; end

    # Class-level kill-switch feature flag accessor consumed by
    # DeprecationCheckJob. Mirrors the per-instance `cohort_feature_flag` hook
    # below — split out as a class method for the same reason as
    # `cohort_identifier`.
    sig { abstract.returns(String) }
    def self.cohort_feature_flag_name; end

    # Per-cohort email enqueue rate limit (deliver_later calls / second),
    # used by the throttling logic in perform_batch. Each cohort tunes this
    # so that the resulting outbound SMTP rate stays under the mailer
    # infrastructure cap of ~500 messages/sec, accounting for cohort-specific
    # BCC fan-out (e.g. ~5.7 admins per org, ~7.1 owners per business, 1 per
    # user). The constant is set on each subclass so the value is visible
    # alongside the rest of the cohort's tuning constants.
    #
    # When tuning these values, watch `api_versioning.enqueue_duration_ms`
    # — that timing includes any throttle sleep applied to the row, so a
    # lower limit will visibly raise the per-row enqueue latency.
    sig { abstract.returns(Integer) }
    def self.email_enqueue_rate_limit; end

    sig do
      params(
        version: String,
        deprecation_date: String,
        latest_version: String,
        wave_identifier: String,
        correlation_id: String,
        offset_entity_id: Integer,
        dry_run: T::Boolean,
        batch_size: Integer,
        pages_processed: Integer,
        estimated_total_pages: Integer,
        target_actor_id: T.nilable(Integer),
      ).void
    end
    def perform(version, deprecation_date:, latest_version:, wave_identifier:, correlation_id:, offset_entity_id: 0, dry_run: false, batch_size: BATCH_SIZE, pages_processed: 0, estimated_total_pages: 0, target_actor_id: nil)
      # Mode dispatcher. target_actor_id and cursor-paging are mutually exclusive
      # because a target run always processes exactly one row and exits — there
      # is nothing to page through. Reject combined args here so the two paths
      # below can each assume their own preconditions and avoid scattering
      # `if target_actor_id` branches throughout the body.
      if target_actor_id && offset_entity_id != 0
        raise ArgumentError, "target_actor_id and offset_entity_id are mutually exclusive"
      end

      if target_actor_id
        perform_target(
          version,
          deprecation_date: deprecation_date,
          latest_version: latest_version,
          wave_identifier: wave_identifier,
          correlation_id: correlation_id,
          target_actor_id: target_actor_id,
        )
      else
        perform_batch(
          version,
          deprecation_date: deprecation_date,
          latest_version: latest_version,
          wave_identifier: wave_identifier,
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

    # The current page's fetched rows. Set by perform_batch immediately after the
    # Kusto fetch, and by perform_target as `[row]`. Available to subclasses
    # that need batch-scoped data prefetching keyed on the page's rows.
    #
    # Lifecycle: `current_rows` is overwritten at the top of every perform_batch
    # / perform_target call. Standard ActiveJob invocations (`perform_now` /
    # `perform_later`) create a fresh instance per call, so any
    # `@foo ||= ...` memo a subclass derives from `current_rows` lives exactly
    # one invocation. There is no cross-page state under idiomatic usage.
    sig { returns(T.nilable(T::Array[T.untyped])) }
    attr_reader :current_rows

    # Per-page id → Business map built once in perform_batch / perform_target
    # right after the Kusto fetch, and consumed per-row by `with_tenant_for`
    # below. Always present (possibly empty) by the time the row loop runs;
    # `nil` only between job construction and the first fetch. Outside
    # Proxima (GitHub.multi_tenant_enterprise? == false) the map is empty
    # and `with_tenant_for` short-circuits without consulting it.
    #
    # Lifecycle mirrors `current_rows`: overwritten at the top of every
    # perform_batch / perform_target invocation, scoped to one ActiveJob
    # invocation under idiomatic usage.
    sig { returns(T.nilable(T::Hash[Integer, Business])) }
    attr_reader :business_map

    # ------------------------------------------------------------------
    # Required cohort-specific hooks
    # ------------------------------------------------------------------

    # The cohort tag string. Persisted as part of Redis keys (running_key /
    # completed_key) and emitted as the `cohort:` dogstats tag — changing this
    # would invalidate live keys and dashboards.
    sig { abstract.returns(String) }
    def cohort; end

    # The cohort-specific kill-switch feature flag name (e.g.
    # "api_versioning_deprecation_emails_users_enabled"). Combined with the
    # global "api_versioning_deprecation_emails_enabled" flag for the
    # mid-batch stopping check.
    sig { abstract.returns(String) }
    def cohort_feature_flag; end

    sig do
      abstract.params(
        version: String,
        offset: Integer,
        batch_size: Integer,
      ).returns(T::Array[T.untyped])
    end
    def fetch_rows(version, offset:, batch_size:); end

    sig { abstract.params(version: String).returns(Integer) }
    def fetch_count(version); end

    sig do
      abstract.params(
        version: String,
        actor_id: Integer,
      ).returns(T::Array[T.untyped])
    end
    def fetch_for_actor(version, actor_id:); end

    sig { abstract.params(actor_ids: T::Array[Integer]).returns(T::Hash[Integer, T.untyped]) }
    def hydrate_actors(actor_ids); end

    sig { abstract.params(actor_id: Integer).returns(T.untyped) }
    def find_actor(actor_id); end

    sig { abstract.params(actor: T.untyped).returns(T::Boolean) }
    def actor_suspended?(actor); end

    # ActionRestraint dedup gate. Returns true if the action should proceed
    # (i.e. the actor has not been notified within wave.send_cadence), false
    # otherwise.
    #
    # Why the *whole* GitHub::ActionRestraint.perform? call lives in the
    # subclass instead of an `extra_kwargs` hook the base class would splat:
    #
    # 1. Persisted-state contract: the actor kwarg name (user_id: / org_id: /
    #    business_id:) is part of the composed Redis dedup key. Changing the
    #    kwarg name re-triggers sends to every actor previously deduped under
    #    the old key. Keeping the literal `ACTION_RESTRAINT_KEY` constant and
    #    its kwarg co-located inside one method (rather than scattered between
    #    a kwargs-builder hook and a base-class call site) makes the persisted
    #    contract trivial to audit: one `grep` per cohort returns the entire
    #    dedup-key recipe.
    #
    # 2. Sorbet correctness: `GitHub::ActionRestraint.perform?` has required
    #    keyword params (`base_key`, `interval:`) plus a `**extra_keys` rest.
    #    Sorbet rejects mixing explicit kwargs with a `**` splat into such a
    #    signature ("Cannot call with a Hash keyword splat because the method
    #    has required keyword parameters"). A `extras_for(actor_id)` hook in
    #    the base class would force `T.unsafe`, silently giving up type
    #    safety on the dedup gate.
    #
    # 3. Readability: a reader scanning the subclass sees the entire dedup
    #    decision in one place — what key, what interval, what kwargs, what
    #    cohort. There is no jump-to-base-class indirection at the most
    #    behaviorally critical step in the row loop.
    sig do
      abstract.params(
        row: T.untyped,
        wave: NotificationWave,
        version: String,
        wave_identifier: String,
      ).returns(T::Boolean)
    end
    def action_restraint_admit?(row, wave:, version:, wave_identifier:); end

    # Build the cohort's mailer and call .deliver_later. The base class times
    # this call externally for `api_versioning.enqueue_duration_ms`, so the
    # subclass body is just "build the mailer + .deliver_later".
    #
    # Subclasses list every mailer kwarg explicitly at the call site. The
    # mailer body is intentionally generic across cohorts — it names the
    # deprecating version and date, nothing more — so there is no
    # per-cohort metadata threaded through this hook.
    sig do
      abstract.params(
        actor: T.untyped,
        row: T.untyped,
        version: String,
        deprecation_date: String,
        latest_version: String,
        subject_prefix: String,
      ).void
    end
    def deliver_mail(actor, row, version:, deprecation_date:, latest_version:, subject_prefix:); end

    # ------------------------------------------------------------------
    # Shared mechanics
    # ------------------------------------------------------------------

    sig do
      params(
        version: String,
        deprecation_date: String,
        latest_version: String,
        wave_identifier: String,
        correlation_id: String,
        offset_entity_id: Integer,
        dry_run: T::Boolean,
        batch_size: Integer,
        pages_processed: Integer,
        estimated_total_pages: Integer,
      ).void
    end
    def perform_batch(version, deprecation_date:, latest_version:, wave_identifier:, correlation_id:, offset_entity_id:, dry_run:, batch_size:, pages_processed:, estimated_total_pages:)
      current_page = pages_processed + 1

      # Measure the entire runtime of perform (including guard checks, Kusto fetch,
      # MySQL hydration, and per-row enqueue work) so api_versioning.batch_duration_ms
      # reflects the full batch — not just the email-send loop.
      job_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)

      # First log line — emitted before any early-return branch so we can always
      # confirm the worker actually picked up an enqueued page. If the previous
      # page logged "enqueued next page" but no "perform invoked" appears here,
      # the job is sitting in the queue (worker backlog) or was dropped before
      # perform was invoked.
      GitHub.logger.info(
        "perform invoked",
        "gh.cohort" => cohort,
        "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id,
        "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
        "gh.correlation_id" => correlation_id,
      )

      wave = DeprecationNotificationWave.for_identifier(wave_identifier)
      unless wave
        GitHub.logger.info(
          "unknown wave_identifier — returning",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier,
          "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      # Per-batch flag re-checks — evaluated on every page so that disabling a flag
      # mid-run stops the pipeline at the next batch boundary rather than mid-batch.
      #
      # Why we delete the running key on stop:
      # The running key acts as a distributed mutex (set NX on the first page). If we
      # simply return here without deleting it, the key lingers for RUNNING_TTL.
      # DeprecationCheckJob skips re-dispatching a cohort when the running key is present,
      # so re-enabling the flag during that window would silently have no effect — the
      # orchestrator would see the stale key and do nothing. Deleting it here lets the
      # orchestrator re-dispatch as soon as it runs after the flag is turned back on.
      stopping_flag = [
        "api_versioning_deprecation_emails_enabled",
        cohort_feature_flag,
      ].find { |flag| !FeatureFlag.vexi.enabled?(flag, default: false) }
      if stopping_flag
        GitHub.logger.info(
          "stopping — #{stopping_flag} is off",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.correlation_id" => correlation_id,
        )
        GitHub.legacy_redis.del(wave.running_key(version: version, cohort: cohort))
        return
      end

      # Re-read dry_run from the flag on every page so a mid-run toggle takes effect,
      # but preserve an explicit dry_run: true passed to the job.
      dry_run ||= FeatureFlag.vexi.enabled?("api_versioning_deprecation_emails_dry_run", default: true)

      # acquired tracks whether *this* invocation set the running key (only possible on
      # the first page, offset_entity_id == 0). It is used in the rescue clause below to
      # decide whether to delete the key on an unhandled exception — we must not touch a
      # running key that a different invocation owns (pages > 0 never set the key).
      acquired = T.let(false, T::Boolean)

      if offset_entity_id == 0
        unless GitHub.legacy_redis.set(
          wave.running_key(version: version, cohort: cohort),
          1,
          nx: true,
          ex: NotificationWave::RUNNING_TTL.to_i,
        )
          GitHub.logger.info(
            "skipping — running key already present",
            "gh.cohort" => cohort,
            "gh.version" => version, "gh.wave" => wave_identifier,
            "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
            "gh.correlation_id" => correlation_id,
          )
          return
        end
        acquired = true
      end

      wave.refresh_running_key!(version: version, cohort: cohort)

      if offset_entity_id == 0
        total = fetch_count(version)
        GitHub.dogstats.gauge("api_versioning.total_cohort_size", total, tags: cohort_tags(version, wave_identifier))
        # Compute estimated_total_pages once on the first page from the cohort count snapshot,
        # then thread it through perform_later so subsequent batches can log progress without re-querying the count.
        #
        # This is an *estimate*, not a bound — hence the gh.estimated_total_pages
        # log key. Termination is driven by has_more_pages (recomputed every page
        # from the actual fetch_rows result), not by current_page vs estimated_total_pages.
        # Two things can drive current_page > estimated_total_pages over a long-running wave:
        #   1. Cohort growth — actors with actor_id > the cursor appear in the
        #      materialized view between the initial fetch_count and later
        #      fetch_rows calls (the dominant cause for multi-hour waves).
        #   2. fetch_count and fetch_rows are independent Kusto queries against
        #      the same MV and can disagree by a few rows at the boundary even
        #      with no real growth.
        # Both are harmless: the page loop stops the moment fetch_rows returns
        # <= batch_size rows.
        estimated_total_pages = (total.to_f / batch_size).ceil
      end

      GitHub.logger.info(
        "starting batch",
        "gh.cohort" => cohort,
        "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id, "gh.current_page" => current_page,
        "gh.estimated_total_pages" => estimated_total_pages, "gh.dry_run" => dry_run,
        "gh.correlation_id" => correlation_id,
      )

      # Fetch one extra row beyond batch_size so we can tell, in this same call,
      # whether a next page exists. If the fetch returned > batch_size rows we
      # know there is more data; if it returned <= batch_size this is the final
      # page. This avoids the otherwise-required "enqueue, fetch zero, mark
      # completed" round-trip when the cohort total is an exact multiple of
      # batch_size.
      kusto_fetch_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      rows = fetch_rows(version, offset: offset_entity_id, batch_size: batch_size + 1)
      GitHub.dogstats.timing(
        "api_versioning.kusto_fetch_duration_ms",
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - kusto_fetch_start) * 1000).round,
        tags: cohort_tags(version, wave_identifier),
      )
      has_more_pages = rows.size > batch_size
      # Discard the peeked-at extra row so it isn't processed twice: the next page
      # will re-fetch it via `where actor_id > offset_id`. When the fetch returned
      # <= batch_size rows this is a no-op (Array#first(n) returns the whole array).
      rows = rows.first(batch_size)

      # Empty page is still possible (e.g. mid-wave the cohort fully drained, or
      # a stale enqueue races a completion). Treat it as a clean terminator.
      if rows.empty?
        emit_estimate_overrun_metric(current_page: current_page, estimated_total_pages: estimated_total_pages, version: version, wave_identifier: wave_identifier)
        GitHub.logger.info(
          "empty page — marking completed",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.completed" => true,
          "gh.correlation_id" => correlation_id,
        )
        wave.mark_completed!(version: version, cohort: cohort)
        return
      end

      # Publish the page rows so any subclass that defines memoized
      # batch-scoped prefetches against `current_rows` can read them.
      @current_rows = T.let(rows, T.nilable(T::Array[T.untyped]))

      # Resolve the per-row tenant context once for the whole page. The map
      # is consumed per-row by `with_tenant_for` below — see that method's
      # docstring for the rationale (in Proxima, setting CurrentTenant before
      # `deliver_later` lets the AJ tenant-context before_enqueue hook stamp
      # X-GitHub-Tenant-* headers onto the serialized MailDeliveryJob so the
      # worker deserializes the recipient in the right tenant DB and sends
      # via the right tenant's mail config).
      @business_map = T.let(build_business_map(rows), T.nilable(T::Hash[Integer, Business]))

      GitHub.logger.info(
        "fetched rows",
        "gh.cohort" => cohort,
        "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id, "gh.row_count" => rows.size,
        "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
        "gh.correlation_id" => correlation_id,
      )

      GitHub.dogstats.count("api_versioning.rows_fetched", rows.size, tags: cohort_tags(version, wave_identifier))

      mysql_hydration_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)

      subject_prefix = DeprecationNotificationWave::SUBJECT_PREFIXES.fetch(wave_identifier, "Action required")

      actor_map = hydrate_actors(rows.map(&:actor_id))
      GitHub.dogstats.timing(
        "api_versioning.mysql_hydration_duration_ms",
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - mysql_hydration_start) * 1000).round,
        tags: cohort_tags(version, wave_identifier),
      )

      emails_sent = 0
      emails_skipped = 0
      not_found_count = 0
      suspended_count = 0
      dry_run_count = 0

      # Marker used by the per-row throttling block below. Captured here
      # (after Kusto fetch and MySQL hydration, immediately before the
      # enqueue loop) so the rate calculation reflects only the time spent
      # actually enqueueing emails — not the upstream I/O — and matches the
      # "deliver_later/sec" units of `email_enqueue_rate_limit`.
      enqueue_loop_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      throttle_total = T.let(0.0, Float)
      rate_limit = self.class.email_enqueue_rate_limit

      last_heartbeat_at = T.let(T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float), Float)

      rows.each_with_index do |row, index|
        # Time the full "enqueue an email" cost for this row — the
        # deliver_later call itself plus any throttle sleep we apply
        # afterwards. We emit this as `api_versioning.enqueue_duration_ms`
        # below so tuning `email_enqueue_rate_limit` visibly moves the
        # metric: a tighter limit ⇒ more sleep ⇒ higher per-row latency.
        row_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)

        outcome = process_row(
          row,
          actor_map: actor_map,
          wave: wave,
          version: version,
          wave_identifier: wave_identifier,
          deprecation_date: deprecation_date,
          latest_version: latest_version,
          subject_prefix: subject_prefix,
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
        # deliver_later calls per second. We only consider real sends
        # (`:sent`) for the rate calculation — skips/dry-runs/etc. don't
        # produce SMTP traffic, so they shouldn't count against the budget.
        # Checked every THROTTLE_CHECK_INTERVAL sends rather than every send
        # to keep clock_gettime overhead negligible.
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
        # meaningless for skips/not_found/suspended/dry_run paths. The
        # window intentionally spans deliver_later + throttle sleep so the
        # operator can correlate `api_versioning.enqueue_duration_ms` with
        # the configured rate limit when tuning.
        if outcome == :sent
          GitHub.dogstats.timing(
            "api_versioning.enqueue_duration_ms",
            ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - row_start) * 1000).round,
            tags: cohort_tags(version, wave_identifier),
          )
        end

        now = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
        if now - last_heartbeat_at >= HEARTBEAT_INTERVAL_SECONDS
          processed_in_batch = index + 1
          GitHub.logger.info(
            "heartbeat — still processing batch",
            "gh.cohort" => cohort,
            "gh.version" => version,
            "gh.wave" => wave_identifier,
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

      tags = cohort_tags(version, wave_identifier)
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
        "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id,
        "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages, "gh.has_more_pages" => has_more_pages,
        "gh.sent" => emails_sent, "gh.skipped" => emails_skipped, "gh.dry_run_count" => dry_run_count,
        "gh.not_found" => not_found_count, "gh.suspended" => suspended_count,
        "gh.throttle_sleep_ms" => (throttle_total * 1000).round,
        "gh.correlation_id" => correlation_id,
      )

      if has_more_pages
        # Backstop the per-page `has_more_pages` termination signal so a
        # continuously-growing cohort cannot keep the chain alive forever.
        # See ESTIMATE_OVERRUN_GRACE_PAGES for sizing rationale. Stragglers
        # past the cap are picked up by the next DeprecationCheckJob dispatch
        # after wave.send_cadence — accepting that wait is the explicit trade
        # against re-walking ~30M actors per cohort daily.
        cap = estimated_total_pages + ESTIMATE_OVERRUN_GRACE_PAGES
        if estimated_total_pages > 0 && current_page >= cap
          overrun_pages = current_page - estimated_total_pages
          GitHub.dogstats.count("api_versioning.estimate_overrun_cap_hit", 1, tags: cohort_tags(version, wave_identifier))
          emit_estimate_overrun_metric(current_page: current_page, estimated_total_pages: estimated_total_pages, version: version, wave_identifier: wave_identifier)
          GitHub.logger.warn(
            "estimate overrun cap hit — marking completed early",
            "gh.cohort" => cohort,
            "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id,
            "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
            "gh.cap" => cap, "gh.overrun_pages" => overrun_pages,
            "gh.send_cadence_seconds" => wave.send_cadence.to_i,
            "gh.completed" => true,
            "gh.correlation_id" => correlation_id,
          )
          wave.mark_completed!(version: version, cohort: cohort)
          return
        end

        next_offset = rows.last.actor_id
        GitHub.logger.info(
          "enqueueing next page",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.next_page" => current_page + 1, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.next_offset" => next_offset, "gh.correlation_id" => correlation_id,
        )
        self.class.perform_later(
          version,
          deprecation_date: deprecation_date,
          latest_version: latest_version,
          wave_identifier: wave_identifier,
          correlation_id: correlation_id,
          offset_entity_id: next_offset,
          dry_run: dry_run,
          batch_size: batch_size,
          pages_processed: current_page,
          estimated_total_pages: estimated_total_pages,
        )
        # Confirmation log — fires only if perform_later returned without raising,
        # so a missing line here (paired with the "enqueueing next page" line above)
        # tells us the enqueue itself raised and was caught upstream.
        GitHub.logger.info(
          "enqueued next page",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier, "gh.offset" => offset_entity_id,
          "gh.current_page" => current_page, "gh.next_page" => current_page + 1, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.next_offset" => next_offset, "gh.correlation_id" => correlation_id,
        )
      else
        emit_estimate_overrun_metric(current_page: current_page, estimated_total_pages: estimated_total_pages, version: version, wave_identifier: wave_identifier)
        GitHub.logger.info(
          "final page — marking completed",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier,
          "gh.pages_processed_total" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.completed" => true,
          "gh.correlation_id" => correlation_id,
        )
        wave.mark_completed!(version: version, cohort: cohort)
      end
    rescue => e
      GitHub.logger.error(
        "terminal exception while processing batch",
        "gh.cohort" => cohort,
        "gh.version" => version,
        "gh.wave" => wave_identifier,
        "gh.offset" => offset_entity_id,
        "gh.current_page" => current_page,
        "gh.estimated_total_pages" => estimated_total_pages,
        "gh.correlation_id" => correlation_id,
        "gh.acquired_running_key" => acquired,
        "gh.error_class" => e.class.name,
        "gh.error" => e.message,
      )

      # If an unhandled exception escapes the batch loop we must delete the running key
      # so that retries (and the next daily DeprecationCheckJob dispatch) can re-acquire
      # it. Without this, the key would linger for RUNNING_TTL and every retry
      # would silently no-op through the "running key already present" guard above.
      #
      # We only delete when *this* invocation acquired the key (acquired == true). Pages
      # beyond the first (offset_entity_id > 0) do not own the key and must not touch it.
      running_key = wave&.running_key(version: version, cohort: cohort)
      if acquired && running_key
        GitHub.logger.info(
          "unhandled exception on page #{offset_entity_id} — releasing running key",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier,
          "gh.current_page" => current_page, "gh.estimated_total_pages" => estimated_total_pages,
          "gh.correlation_id" => correlation_id, "gh.error" => e.message,
        )
        GitHub.legacy_redis.del(running_key)
      end
      raise
    end

    sig do
      params(
        version: String,
        deprecation_date: String,
        latest_version: String,
        wave_identifier: String,
        correlation_id: String,
        target_actor_id: Integer,
      ).void
    end
    def perform_target(version, deprecation_date:, latest_version:, wave_identifier:, correlation_id:, target_actor_id:)
      GitHub.logger.info(
        "target run invoked",
        "gh.cohort" => cohort,
        "gh.version" => version, "gh.wave" => wave_identifier,
        "gh.target_actor_id" => target_actor_id,
        "gh.correlation_id" => correlation_id,
      )

      wave = DeprecationNotificationWave.for_identifier(wave_identifier)
      unless wave
        GitHub.logger.info(
          "target run — unknown wave_identifier",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier,
          "gh.target_actor_id" => target_actor_id,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      # Same stopping-flag semantics as batch mode: if globally disabled, do
      # nothing. We have not yet acquired the running key here so there is no
      # lock to release.
      stopping_flag = [
        "api_versioning_deprecation_emails_enabled",
        cohort_feature_flag,
      ].find { |flag| !FeatureFlag.vexi.enabled?(flag, default: false) }
      if stopping_flag
        GitHub.logger.info(
          "target run stopping — #{stopping_flag} is off",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier,
          "gh.target_actor_id" => target_actor_id,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      dry_run = FeatureFlag.vexi.enabled?("api_versioning_deprecation_emails_dry_run", default: true)

      # Acquire the wave's NX mutex so a target run cannot race a real wave
      # dispatch (and vice-versa). If the key is already held by another job
      # we bail without doing anything; the holder will release it when done.
      unless GitHub.legacy_redis.set(
        wave.running_key(version: version, cohort: cohort),
        1,
        nx: true,
        ex: NotificationWave::RUNNING_TTL.to_i,
      )
        GitHub.logger.info(
          "target run skipped — running key held",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier,
          "gh.target_actor_id" => target_actor_id,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      begin
        rows = fetch_for_actor(version, actor_id: target_actor_id)

        if rows.empty?
          # Empty result means the targeted actor is no longer in the cohort
          # (e.g. already upgraded). We must NOT call mark_completed! — the
          # rest of the cohort still needs processing.
          GitHub.logger.info(
            "target actor not found in cohort — exiting",
            "gh.cohort" => cohort,
            "gh.version" => version, "gh.wave" => wave_identifier,
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
        subject_prefix = DeprecationNotificationWave::SUBJECT_PREFIXES.fetch(wave_identifier, "Action required")

        # Time the deliver_later call so target-mode sends are visible in the
        # same `api_versioning.enqueue_duration_ms` series as batch-mode
        # sends. Target mode has no throttle, so the timing here is just the
        # deliver_later cost — dashboards can split on the `mode:target` tag
        # below if needed.
        row_start = T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
        outcome = process_row(
          row,
          actor_map: actor_map,
          wave: wave,
          version: version,
          wave_identifier: wave_identifier,
          deprecation_date: deprecation_date,
          latest_version: latest_version,
          subject_prefix: subject_prefix,
          dry_run: dry_run,
        )

        if outcome == :sent
          GitHub.dogstats.timing(
            "api_versioning.enqueue_duration_ms",
            ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - row_start) * 1000).round,
            tags: cohort_tags(version, wave_identifier) + ["mode:target"],
          )
        end

        # Tag with mode:target so dashboards can separate operator-targeted
        # sends from the daily wave traffic without distorting wave totals.
        tags = cohort_tags(version, wave_identifier) + ["mode:target"]
        GitHub.dogstats.count("api_versioning.#{outcome_metric(outcome)}", 1, tags: tags)

        GitHub.logger.info(
          "target run complete",
          "gh.cohort" => cohort,
          "gh.version" => version, "gh.wave" => wave_identifier,
          "gh.target_actor_id" => target_actor_id,
          "gh.outcome" => outcome.to_s,
          "gh.completed" => true,
          "gh.correlation_id" => correlation_id,
        )
      ensure
        # Always release the lock — target mode never calls mark_completed!
        # (that would suppress real wave dispatches for the rest of the
        # cadence window) and must not leave a stale lock blocking the next
        # dispatch on either success or failure.
        GitHub.legacy_redis.del(wave.running_key(version: version, cohort: cohort))
      end
    rescue => e
      GitHub.logger.error(
        "terminal exception during target run",
        "gh.cohort" => cohort,
        "gh.version" => version,
        "gh.wave" => wave_identifier,
        "gh.target_actor_id" => target_actor_id,
        "gh.correlation_id" => correlation_id,
        "gh.error_class" => e.class.name,
        "gh.error" => e.message,
      )
      raise
    end

    # Shared per-row delivery logic used by both perform_batch and
    # perform_target. Returns a Symbol describing the outcome so each caller
    # can aggregate however it likes (counters in batch, single value in
    # target). Does NOT raise on missing/suspended actors — those are normal
    # outcomes that the caller records and moves on from.
    sig do
      params(
        row: T.untyped,
        actor_map: T::Hash[Integer, T.untyped],
        wave: NotificationWave,
        version: String,
        wave_identifier: String,
        deprecation_date: String,
        latest_version: String,
        subject_prefix: String,
        dry_run: T::Boolean,
      ).returns(Symbol)
    end
    def process_row(row, actor_map:, wave:, version:, wave_identifier:, deprecation_date:, latest_version:, subject_prefix:, dry_run:)
      # Skip ActionRestraint during dry runs so dedup keys are not written.
      # Writing keys during a dry run would block real sends on the next live run.
      unless dry_run
        unless action_restraint_admit?(row, wave: wave, version: version, wave_identifier: wave_identifier)
          return :skipped
        end
      end

      actor = actor_map[row.actor_id]
      return :not_found unless actor
      return :suspended if actor_suspended?(actor)

      return :dry_run if dry_run

      # Note: timing of the deliver_later call is captured by the caller
      # (perform_batch / perform_target) so the emitted
      # `api_versioning.enqueue_duration_ms` can include any throttle sleep
      # applied around this row.
      #
      # The deliver_mail call is wrapped in `with_tenant_for` so that, in
      # Proxima, GitHub::CurrentTenant is set to the row's owning Business
      # at the moment .deliver_later runs. The AJ tenant-context
      # before_enqueue hook reads the thread-local tenant and stamps
      # X-GitHub-Tenant-* headers onto the serialized MailDeliveryJob
      # payload; without this wrap, a cross-tenant batch (legal in Proxima
      # because the MV summarizes by tenant_id) would enqueue every mail
      # delivery job with no tenant header, and the worker would deserialize
      # the recipient User GID against the wrong DB and/or send through the
      # wrong tenant's mail config.
      #
      # The email body itself is intentionally generic (no tenant-specific
      # URLs), so the wrap is purely about the enqueue-time header
      # stamping — not about anything rendered inside the mailer templates.
      #
      # Outside Proxima `with_tenant_for` is a no-op pass-through. Returns
      # false when the row's tenant_id couldn't be resolved (logged at warn
      # level inside the helper); we treat that as a skip rather than a
      # hard failure so the rest of the page proceeds. The unresolved-tenant
      # path also increments a dedicated `skipped_unresolved_tenant`
      # counter so the dashboard / alerting can distinguish this (it should
      # be ~0 in steady state) from the generic `skipped` bucket it rolls
      # into.
      delivered = with_tenant_for(row) do
        deliver_mail(
          actor,
          row,
          version: version,
          deprecation_date: deprecation_date,
          latest_version: latest_version,
          subject_prefix: subject_prefix,
        )
      end
      unless delivered
        GitHub.dogstats.increment(
          "api_versioning.skipped_unresolved_tenant",
          tags: cohort_tags(version, wave_identifier),
        )
        return :skipped
      end

      :sent
    end

    # Maps a #process_row outcome symbol to the matching dogstats metric
    # suffix used in target-mode reporting. Kept aligned with the batch
    # counters above (sent / skipped / skipped_not_found / skipped_suspended /
    # dry_run) so dashboards can sum across modes.
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

    sig { params(version: String, wave_identifier: String).returns(T::Array[String]) }
    def cohort_tags(version, wave_identifier)
      ["version:#{version}", "wave:#{wave_identifier}", "email_type:deprecation", "cohort:#{cohort}"]
    end

    # Resolve the tenant Business records for a page of cohort rows. Used by
    # perform_batch / perform_target right after the Kusto fetch to publish
    # `@business_map`, which `with_tenant_for` consults per-row.
    #
    # Outside Proxima (multi_tenant_enterprise? == false) cohort rows have no
    # tenant_id (the dotcom materialized views don't project the column), so
    # we short-circuit to an empty map and `with_tenant_for` becomes a no-op
    # pass-through. In Proxima the MVs summarize by tenant_id so a single
    # batch can span multiple tenants — we look them all up in one query and
    # index by id so the per-row helper is an O(1) hash read.
    #
    # Rows whose `tenant_id` does not resolve to a Business (deleted tenant,
    # data drift between Kusto and MySQL, etc.) are not included in the map;
    # `with_tenant_for` treats them as skipped via the same warn-log path it
    # uses for rows with a nil tenant_id.
    sig { params(rows: T::Array[T.untyped]).returns(T::Hash[Integer, Business]) }
    def build_business_map(rows)
      return {} unless GitHub.multi_tenant_enterprise?

      tenant_ids = rows.filter_map(&:tenant_id).uniq
      return {} if tenant_ids.empty?

      Business.where(id: tenant_ids).index_by(&:id)
    end

    # Run a block with GitHub::CurrentTenant set to the Business that owns
    # the row's tenant_id. Returns true if the block ran, false if the row
    # had to be skipped because its tenant could not be resolved.
    #
    # Outside Proxima this is a no-op pass-through (the block runs, true is
    # returned). Inside Proxima the block runs inside a CurrentTenant.set
    # frame so that the AJ tenant-context before_enqueue hook, when the
    # mailer calls `.deliver_later`, stamps X-GitHub-Tenant-* headers onto
    # the serialized MailDeliveryJob payload. The worker uses those headers
    # to deserialize the recipient User GID against the correct tenant DB
    # and to send through the correct tenant's mail config. Without this
    # wrap, a cross-tenant batch (legal in Proxima because the MV
    # summarizes by tenant_id) would enqueue every deliver job with no
    # tenant header.
    #
    # This is the same pattern other cross-tenant batched mailer jobs use
    # — e.g. NotifyExpiredTrialsJob, DeleteExpiredTrialsJob,
    # ScanEmuOrganizationUsersJob — factored into a helper here because
    # the row loop is tight and we pre-resolve tenants into `business_map`
    # so the per-row lookup is O(1).
    #
    # Note: this is NOT about anything the mailer renders — the email body
    # is intentionally generic (no tenant-specific URLs). It is purely
    # about the enqueue-time tenant header on the downstream
    # MailDeliveryJob.
    #
    # `GitHub::CurrentTenant.set(business) { ... }` clears the thread-local
    # on exit; it does not restore a prior value. That is safe here because
    # this job is wrapped in `GitHub::CurrentTenant.unscope` by
    # ActiveJob::TenantContext's around_perform (via
    # `exempt_from_tenant_context_requirement` on each cohort subclass), so
    # each row enters with tenant == nil.
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

    # Emit the per-wave drift between the page-zero estimate and where the
    # chain actually terminated. Floored at zero — a chain that ended early
    # (empty page before the estimate) reports 0 rather than a negative
    # number, since the metric's purpose is sizing ESTIMATE_OVERRUN_GRACE_PAGES.
    sig do
      params(
        current_page: Integer,
        estimated_total_pages: Integer,
        version: String,
        wave_identifier: String,
      ).void
    end
    def emit_estimate_overrun_metric(current_page:, estimated_total_pages:, version:, wave_identifier:)
      overrun = [current_page - estimated_total_pages, 0].max
      GitHub.dogstats.gauge(
        "api_versioning.estimate_overrun_pages",
        overrun,
        tags: cohort_tags(version, wave_identifier),
      )
    end
  end
end
