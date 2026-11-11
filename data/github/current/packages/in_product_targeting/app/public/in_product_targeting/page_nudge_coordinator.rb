# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Request-scoped coordinator that resolves which nudges win the priority
  # contest on a page, so independent nudge code paths (top banner, sidebar
  # cards, …) stop crowding each other out.
  #
  # See ADR "Cross-Surface Nudge Priority Coordination" Step 4
  # (github/in-product-messaging, docs/dev/adr/nudge-priority-coordination/).
  #
  # Usage:
  #
  #   coordinator = InProductTargeting::PageNudgeCoordinator.for(
  #     page: :org_overview, user: current_user, context: context,
  #   )
  #   if coordinator.winners.include?(:my_nudge_id)
  #     payload[:nudges] << serialize_my_nudge(...)
  #     coordinator.confirm_render!(:my_nudge_id)
  #   end
  #
  # `.for` is gated on the FEATURE_FLAG below (default off): while disabled it
  # returns a single shared inert coordinator whose decision has no winners, no
  # losers, and an empty suppression buffer, so a call site is a no-op until the
  # flag is enabled.
  class PageNudgeCoordinator
    # Framework-level kill switch (default off). Per-page flags
    # (in_product_messaging_priority_coordinator_<page_key>) are introduced
    # later, as each page is migrated per the ADR rollout.
    FEATURE_FLAG = "in_product_messaging_priority_coordinator"

    # Contest sort order, derived from the registry's tier vocabulary so a
    # tier added there is automatically sortable here.
    TIER_SORT_ORDER = T.let(
      PriorityRegistry::TIERS.each_with_index.to_h.freeze,
      T::Hash[Symbol, Integer],
    )

    SUPPRESSED_EVENT = "in_product_targeting.nudge_suppressed"
    SUPPRESSION_ORPHANED_EVENT = "in_product_targeting.nudge_suppression_orphaned"
    SUPPRESSED_ACTION = "suppressed"
    SUPPRESSION_ORPHANED_ACTION = "suppression_orphaned"

    # Single source of truth for the `key:value;`-delimited suppression label
    # micro-format consumed by analytics. Tests assert against this helper
    # rather than re-spelling the format; the inputs are Symbols validated
    # against PriorityRegistry::IDENTIFIER_FORMAT at registration time, so
    # they cannot inject the delimiters.
    sig { params(lost_to: Symbol, tier: Symbol, page: Symbol, reason: Symbol).returns(String) }
    def self.suppression_label(lost_to:, tier:, page:, reason:)
      "lost_to:#{lost_to};tier:#{tier};page:#{page};reason:#{reason}"
    end

    # Raised (and reported via the per-candidate rescue in #decide) when an
    # eligibility proc consults coordinator.winners/losers: the contest is
    # still running, so re-entering it would recurse without bound.
    class ReentrantContestError < StandardError; end

    # Reported (never raised) when a call site passes `.for` a context that
    # differs from the one the request's coordinator was constructed with.
    class StaleContextError < StandardError; end

    # One buffered suppression: which nudge lost, which winner it is
    # initially attributed to (re-attributed at flush time if that winner
    # never confirmed render), and which cap evicted it.
    class Suppression < T::Struct
      const :loser_id, Symbol
      const :winner_id, T.nilable(Symbol)
      const :reason, Symbol # :surface_cap | :page_cap
    end

    # Immutable value object holding the contest result: every collection is
    # frozen at construction, so it is safe to hand to downstream serializers
    # without exposing the coordinator's mutable hooks.
    class Decision < T::Struct
      const :winners, T::Set[Symbol]
      const :losers, T::Set[Symbol]
      const :suppression_reasons, T::Hash[Symbol, Symbol]
      const :suppression_buffer, T::Array[Suppression]
    end

    INERT_DECISION = T.let(
      Decision.new(
        winners: Set.new.freeze,
        losers: Set.new.freeze,
        suppression_reasons: {}.freeze,
        suppression_buffer: [].freeze,
      ).freeze,
      Decision,
    )

    sig { returns(Symbol) }
    attr_reader :page

    # nil only for the shared inert coordinator (disabled path).
    sig { returns(T.nilable(::User)) }
    attr_reader :user

    # Returns the coordinator instance for this request, creating it on first
    # call. Request-scoped via InProductTargeting::RequestStore.
    #
    # When the flag is disabled this returns the shared inert coordinator
    # without touching the request store, so the disabled path costs one flag
    # check and allocates nothing — no per-[page, user] coordinator,
    # EligibilityCall, or Sets. The flag is request-stable (vexi), so a request
    # never observes a mix of enabled and inert coordinators.
    #
    # When enabled, the coordinator is keyed on [page, user.id] only —
    # deliberately NOT on context. Different call sites on the same page render
    # (controller view + sidebar partial + payload generator) build their own
    # context objects, and keying on context would split them into separate
    # coordinator instances and break suppression/on_win accounting. The first
    # call's context wins; a later call whose context carries different values
    # gets a Failbot report so the discrepancy is diagnosable. A page that
    # legitimately needs distinct contexts in one request should use distinct
    # `page:` symbols.
    #
    # Request threads only: RequestStore is backed by CurrentAttributes,
    # which is per-thread and reset by the Rails executor. A coordinator
    # created on a non-request thread (pooled promise renderer, background
    # job) lands in a store the suppression flush never sees — and, if that
    # thread is not executor-wrapped, one that is never reset.
    sig { params(page: Symbol, user: ::User, context: PageContext).returns(PageNudgeCoordinator) }
    def self.for(page:, user:, context:)
      return inert unless FeatureFlag.vexi.enabled?(FEATURE_FLAG, user, default: false)

      coordinators = RequestStore.coordinators!

      existing = coordinators[[page, user.id]]
      if existing
        report_stale_context(existing, context, page)
        return existing
      end

      coordinators[[page, user.id]] = new(page: page, user: user, context: context, enabled: true)
    end

    # Diagnostic-only guard behind `.for`: reports (never raises) when a later
    # call site hands a context differing from the request's first for this
    # [page, user]. The first context wins regardless — this only surfaces the
    # discrepancy. Contained the way eligibility procs are in #decide: a prop
    # whose `==` raises degrades to a Failbot report rather than breaking `.for`,
    # the request's hot path.
    sig { params(existing: PageNudgeCoordinator, context: PageContext, page: Symbol).void }
    def self.report_stale_context(existing, context, page)
      return if existing.send(:context_matches?, context)

      Failbot.report(
        StaleContextError.new(
          "PageNudgeCoordinator.for received a context differing from the " \
          "request's first for this [page, user]; the first context wins.",
        ),
        page: page,
      )
    rescue => e
      Failbot.report(e, page: page)
    end
    private_class_method :report_stale_context

    # `user`/`context` are nil only for the shared inert coordinator (the
    # disabled path), which never runs the contest or its hooks and so never
    # reads them. Every enabled coordinator built by `.for` carries both.
    sig do
      params(page: Symbol, user: T.nilable(::User), context: T.nilable(PageContext), enabled: T::Boolean).void
    end
    def initialize(page:, user:, context:, enabled: true)
      @page = page
      @user = user
      @context = context
      @enabled = enabled
      @decision = T.let(nil, T.nilable(Decision))
      @deciding = T.let(false, T::Boolean)
      # Built lazily (see #eligibility_call) so the disabled path, which never
      # runs eligibility/on_win procs, allocates no argument object.
      @eligibility_call = T.let(nil, T.nilable(PriorityRegistry::EligibilityCall))
      @exempt_tiers = T.let(nil, T.nilable(T::Array[Symbol]))
      @confirmed_renders = T.let(Set.new, T::Set[Symbol])
      @on_win_fired = T.let(Set.new, T::Set[Symbol])
      @suppressions_flushed = T.let(false, T::Boolean)
      # Sorted eligible candidates / winners, captured by #decide so
      # confirm_render! and the suppression flush can look registrations back
      # up by id without re-consulting the registry.
      @candidates_by_id = T.let({}, T::Hash[Symbol, PriorityRegistry::Registration])
      @sorted_winners = T.let([], T::Array[PriorityRegistry::Registration])
    end
    private_class_method :new

    @inert = T.let(nil, T.nilable(PageNudgeCoordinator))

    # Shared inert coordinator returned by `.for` when the framework is
    # disabled. It holds no per-request state (sentinel page, nil user/context),
    # every decision read returns INERT_DECISION, and every hook no-ops, so a
    # single instance is safe to share across all requests and threads. Avoids
    # the per-[page, user] allocation on the disabled path.
    #
    # Built lazily (not as a load-time constant): the constructor reads
    # PriorityRegistry::Registration, which is not yet defined while this class
    # is being loaded through PriorityRegistry's own autoload.
    sig { returns(PageNudgeCoordinator) }
    def self.inert
      @inert ||= new(page: :__inert__, user: nil, context: nil, enabled: false)
    end

    sig { returns(T::Boolean) }
    def enabled?
      @enabled
    end

    # Memoized lazy contest result: the first read runs the contest,
    # subsequent reads return the cached Decision. Re-entrant reads (an
    # eligibility proc consulting coordinator.winners while the contest is
    # running) raise ReentrantContestError instead of recursing.
    sig { returns(Decision) }
    def decision
      # The shared inert coordinator (disabled path) holds no per-request
      # state; returning the frozen constant directly keeps it mutation- and
      # side-effect-free, so a single instance is safe to share across threads.
      return INERT_DECISION unless @enabled

      if @deciding
        raise ReentrantContestError,
          "PageNudgeCoordinator#decision re-entered while the contest was " \
          "running. Eligibility procs must not consult coordinator.winners/" \
          "losers — the contest has not resolved yet when they run."
      end

      @decision ||= begin
        @deciding = true
        decide
      ensure
        @deciding = false
      end
    end

    # Whether the contest has run. The suppression flush checks this so a
    # coordinator that was created but never consulted does not run its
    # eligibility procs after the response is already built.
    sig { returns(T::Boolean) }
    def decided?
      !@decision.nil?
    end

    sig { returns(T::Set[Symbol]) }
    def winners
      decision.winners
    end

    sig { returns(T::Set[Symbol]) }
    def losers
      decision.losers
    end

    # ---- Winner-side hooks ------------------------------------------------

    # Called by the winning render path at the moment of serialization (or
    # render). Idempotent: the first call per winner records the confirmed
    # render and fires the registered `on_win:` proc; later calls no-op, so
    # payloads that re-serialize don't double-log exposures.
    sig { params(nudge_id: Symbol).void }
    def confirm_render!(nudge_id)
      return unless decision.winners.include?(nudge_id)
      return unless @confirmed_renders.add?(nudge_id)

      fire_on_win!(nudge_id)
    end

    # ---- Suppression telemetry flush (ADR Step 7) -------------------------

    # Emits the buffered suppression events, once per request. Called by
    # SuppressionFlusher at the end of the request, after winners have had
    # the chance to confirm_render!.
    #
    # For each buffered loser:
    # - if its attributed winner confirmed render, emit `nudge_suppressed`;
    # - otherwise re-attribute to another confirmed winner on the loser's
    #   surface, then to any confirmed winner on the page;
    # - if no winner confirmed at all, emit `nudge_suppression_orphaned`
    #   instead, so no `suppressed` event lies about who won.
    sig { void }
    def flush_suppression_events!
      return unless @enabled && decided?
      return if @suppressions_flushed

      @suppressions_flushed = true

      # Failures are isolated per suppression: the flush is idempotent, so an
      # entry skipped because an earlier one raised (a failing synchronous
      # subscriber, say) would be lost for good.
      decision.suppression_buffer.each do |suppression|
        loser = @candidates_by_id[suppression.loser_id]
        if loser.nil?
          Failbot.report(
            KeyError.new("no registration captured for suppressed nudge #{suppression.loser_id}"),
            page: @page,
          )
          next
        end

        winner_id = confirmed_attribution_for(suppression, loser)

        if winner_id
          instrument_suppression(
            SUPPRESSED_EVENT,
            action: SUPPRESSED_ACTION,
            loser: loser,
            lost_to: winner_id,
            reason: suppression.reason,
          )
        else
          instrument_suppression(
            SUPPRESSION_ORPHANED_EVENT,
            action: SUPPRESSION_ORPHANED_ACTION,
            loser: loser,
            lost_to: :none,
            reason: suppression.reason,
          )
        end
      rescue => e
        Failbot.report(e, nudge_id: suppression.loser_id, page: @page)
      end
    end

    private

    # ---- Contest ----------------------------------------------------------

    sig { returns(Decision) }
    def decide
      candidates = PriorityRegistry.nudges_for_page(@page)
      eligible = candidates.select do |candidate|
        # A raising eligibility proc must not take down the page (or starve
        # the other candidates): report it and treat the nudge as ineligible.
        begin
          !!candidate.eligibility.call(eligibility_call)
        rescue => e
          Failbot.report(e, nudge_id: candidate.id, page: @page)
          false
        end
      end
      # Stable, autoload-independent ordering: tier, then the explicit
      # per-registration order, then id as the final fallback.
      sorted = eligible.sort_by { |c| [TIER_SORT_ORDER.fetch(c.tier), c.order, c.id.to_s] }

      winners, suppression_reasons = apply_caps(sorted)
      # A candidate lost iff apply_caps recorded a suppression reason for it.
      losers = sorted.select { |candidate| suppression_reasons.key?(candidate.id) }

      @candidates_by_id = sorted.index_by(&:id)
      @sorted_winners = winners

      Decision.new(
        winners: winners.map(&:id).to_set.freeze,
        losers: losers.map(&:id).to_set.freeze,
        suppression_reasons: suppression_reasons.freeze,
        suppression_buffer: buffer_suppressions(losers, winners, suppression_reasons).freeze,
      )
    end

    # Walks the sorted eligible candidates applying the page's caps. Returns
    # the winners (still sorted) and a {loser_id => reason} hash.
    sig do
      params(sorted: T::Array[PriorityRegistry::Registration])
        .returns([T::Array[PriorityRegistry::Registration], T::Hash[Symbol, Symbol]])
    end
    def apply_caps(sorted)
      page_cap = PriorityRegistry.max_visible_for(@page)        # nil = no page-wide cap
      surface_caps = PriorityRegistry.surface_caps_for(@page)   # {} = no per-surface caps

      winners = T.let([], T::Array[PriorityRegistry::Registration])
      suppression_reasons = T.let({}, T::Hash[Symbol, Symbol])
      surface_counts = T.let(Hash.new(0), T::Hash[Symbol, Integer])
      page_count = T.let(0, Integer)

      sorted.each do |candidate|
        # Exempt tiers (legally-required transactional messages by default) are
        # ADDITIVE: they always render and consume NO cap slot — neither the
        # page-wide count nor their surface's count — so a required notice never
        # evicts an otherwise-eligible nudge. This is the confirmed ADR semantics
        # (the worked example wins over the pseudo-code, which had exempt nudges
        # consume a slot): caps limit discretionary clutter, and suppressing a
        # legitimate nudge to make room for a legal notice would lose a real
        # impression for no benefit. Trade-off: a page may show one extra banner
        # when a required message coincides with a full surface — intended, and
        # rare since transactional banners are infrequent.
        if exempt_tier?(candidate.tier)
          winners << candidate
          next
        end

        surface_cap = surface_caps[candidate.surface]
        if surface_cap && surface_counts.fetch(candidate.surface, 0) >= surface_cap
          suppression_reasons[candidate.id] = :surface_cap
          next
        end

        if page_cap && page_count >= page_cap
          suppression_reasons[candidate.id] = :page_cap
          next
        end

        winners << candidate
        surface_counts[candidate.surface] = surface_counts.fetch(candidate.surface, 0) + 1
        page_count += 1
      end

      [winners, suppression_reasons]
    end

    # Suppression is BUFFERED here, not emitted. We don't yet know which
    # winner actually rendered — emission happens in
    # flush_suppression_events! once confirm_render! calls are in.
    sig do
      params(
        losers: T::Array[PriorityRegistry::Registration],
        winners: T::Array[PriorityRegistry::Registration],
        suppression_reasons: T::Hash[Symbol, Symbol],
      ).returns(T::Array[Suppression])
    end
    def buffer_suppressions(losers, winners, suppression_reasons)
      losers.map do |loser|
        Suppression.new(
          loser_id: loser.id,
          winner_id: attribute_winner(loser, winners),
          reason: suppression_reasons.fetch(loser.id),
        )
      end
    end

    # Initial attribution: prefer a winner on the loser's own surface (the
    # most informative for telemetry — that's the winner most likely to have
    # evicted it), falling back to the first sorted winner (the highest-tier
    # nudge on the page).
    #
    # Exempt-tier winners are de-prioritized: they consume no cap slot, so they
    # never actually evicted the loser and "lost_to: <exempt nudge>" would be
    # misleading. They are used only when every winner on the page is exempt.
    sig do
      params(
        loser: PriorityRegistry::Registration,
        winners: T::Array[PriorityRegistry::Registration],
      ).returns(T.nilable(Symbol))
    end
    def attribute_winner(loser, winners)
      pool = winners.reject { |winner| exempt_tier?(winner.tier) }
      pool = winners if pool.empty?
      (pool.find { |winner| winner.surface == loser.surface } || pool.first)&.id
    end

    # Runs the registered `on_win:` proc exactly once per winner per request.
    # `on_win` is where variant exposures, last_shown_at updates, and any
    # other side effect that should only happen when a nudge truly rendered
    # live. Eligibility procs stay predicate-only.
    sig { params(nudge_id: Symbol).void }
    def fire_on_win!(nudge_id)
      return unless @on_win_fired.add?(nudge_id)

      on_win = @candidates_by_id[nudge_id]&.on_win
      return if on_win.nil?

      begin
        on_win.call(eligibility_call)
      rescue => e
        # confirm_render! runs at serialization time; a raising hook (these
        # do I/O by design) must not abort the page mid-render.
        Failbot.report(e, nudge_id: nudge_id, page: @page)
      end
    end

    # Flush-time re-attribution (ADR Step 7): the buffered winner only counts
    # if it confirmed render; otherwise prefer another confirmed winner on the
    # loser's surface, then any confirmed winner. nil = orphaned.
    sig do
      params(
        suppression: Suppression,
        loser: PriorityRegistry::Registration,
      ).returns(T.nilable(Symbol))
    end
    def confirmed_attribution_for(suppression, loser)
      confirmed = @confirmed_renders

      attributed = suppression.winner_id
      return attributed if attributed && confirmed.include?(attributed)

      # Prefer a confirmed non-exempt winner (one that actually consumed a cap
      # slot) on the loser's surface, then any confirmed non-exempt winner;
      # only fall back to a confirmed exempt winner if none rendered.
      [false, true].each do |allow_exempt|
        eligible = @sorted_winners.select do |winner|
          confirmed.include?(winner.id) && (allow_exempt || !exempt_tier?(winner.tier))
        end
        next if eligible.empty?

        winner = eligible.find { |w| w.surface == loser.surface } || T.must(eligible.first)
        return winner.id
      end

      nil
    end

    sig do
      params(
        event: String,
        action: String,
        loser: PriorityRegistry::Registration,
        lost_to: Symbol,
        reason: Symbol,
      ).void
    end
    def instrument_suppression(event, action:, loser:, lost_to:, reason:)
      GlobalInstrumenter.instrument(event, {
        actor: @user,
        category: loser.category,
        action: action,
        label: self.class.suppression_label(lost_to: lost_to, tier: loser.tier, page: @page, reason: reason),
        # `location` is for in-process subscribers only. The Hydro forwarder
        # (config/instrumentation/in_product_targeting.rb) maps just
        # category/action/label into github.analytics.v0.Event; downstream, the
        # page rides in the label's `page:` segment, not here.
        location: @page.to_s,
      })
    end

    # The single argument object handed to eligibility and on_win procs. Built
    # lazily and memoized: only the enabled path reaches this, so the shared
    # inert coordinator (nil user/context) never constructs it.
    sig { returns(PriorityRegistry::EligibilityCall) }
    def eligibility_call # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
      @eligibility_call ||= PriorityRegistry::EligibilityCall.new(
        coordinator: self,
        user: T.must(@user),
        context: T.must(@context),
      )
    end

    # The page's cap-exempt tiers, memoized. Exempt-tier winners consume no cap
    # slot, which both the cap walk and suppression attribution care about.
    sig { params(tier: Symbol).returns(T::Boolean) }
    def exempt_tier?(tier)
      exempt_tiers.include?(tier)
    end

    sig { returns(T::Array[Symbol]) }
    def exempt_tiers # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
      @exempt_tiers ||= PriorityRegistry.cap_exempt_tiers_for(@page)
    end

    # Whether `context` carries the same class and prop values as the context
    # this coordinator was constructed with. Used by `.for` to detect a later
    # call site passing a differently-populated context.
    #
    # Best-effort and diagnostic-only: it compares each declared prop with `==`,
    # so it is only as reliable as the props' `==`. A prop compared by reference
    # identity can mask a real difference (a false match — nothing fires), which
    # is why PageContext subclasses should carry value-comparable props (see
    # PageContext). The caller (report_stale_context) contains a raising `==`.
    sig { params(context: PageContext).returns(T::Boolean) }
    def context_matches?(context)
      return false unless context.class == @context.class

      # Reflective per-prop value comparison: T::Struct has no value `==`, and a
      # context prop may be a non-serializable type (e.g. an Organization), so
      # each declared prop is read directly.
      context.class.props.keys.all? do |prop|
        context.send(prop) == @context.send(prop) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end
    end
  end
end
