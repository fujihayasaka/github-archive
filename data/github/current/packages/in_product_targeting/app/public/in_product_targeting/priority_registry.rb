# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Central registry of nudge registrations and per-page cap configuration for
  # InProductTargeting::PageNudgeCoordinator.
  #
  # See ADR "Cross-Surface Nudge Priority Coordination" Steps 2 and 3
  # (github/in-product-messaging, docs/dev/adr/nudge-priority-coordination/).
  #
  # SCOPES & PAGE HIERARCHY
  # A registration's `page:` is the *scope* a nudge lives in — either a concrete
  # page key (`:repo_overview`) or a broader scope (`:repo`, `:org`, `:global`).
  # A concrete page declares which broader scopes roll up into it via
  # `configure_page(scopes:)`; `:global` rolls up into every page implicitly; and
  # scopes nest transitively. The contest on a concrete page runs over the union
  # of nudges registered at the page and at every scope in its chain
  # (`scopes_for`), under that page's caps — so a banner spanning many pages is
  # registered ONCE at the broadest scope it covers instead of fanned out per
  # page:
  #
  #   register(id: :tos_update, page: :global, …)           # every page
  #   register(id: :repo_nag,   page: :repo, …)             # every repo page
  #   configure_page(key: :repo_overview, scopes: [:repo])  # repo_overview ⊇ repo ⊇ global
  #
  # On :repo_overview, {:repo_overview-specific, :repo, :global} nudges all
  # contest together. When the same nudge is reachable twice on one page (e.g.
  # registered at both :global and a page), that collision is rejected at load by
  # `freeze!` (see validate_scopes!), so the fan-out can't silently double-count.
  #
  # The registry is a process-global that is populated by the canonical
  # registration files (required at the bottom of this file) and then frozen by
  # the `freeze!` call there, which runs when this file is first loaded — lazily,
  # on first use, post-boot. It is deliberately NOT frozen from a boot
  # initializer: referencing the registry from a to_prepare/after_initialize hook
  # would autoload it (and PageNudgeCoordinator and User) during app boot,
  # tripping the lazy-load guard (test/integration/environment_test.rb). After
  # `freeze!`, `register` and `configure_page` raise so an accidentally
  # late-loaded initializer fails loudly instead of quietly mutating global
  # state mid-request. Tests use the block-scoped `with_test_registration`
  # instead of registering directly. Real registrations land in later PRs, one
  # page at a time, per the ADR rollout.
  class PriorityRegistry
    # Raised when `register` or `configure_page` is called after `freeze!`.
    class FrozenRegistryError < StandardError; end

    # The only priority vocabulary (ADR Step 1). Order matters:
    # PageNudgeCoordinator::TIER_SORT_ORDER, the contest sort order, is
    # derived from it.
    TIERS = T.let(%i[transactional triggered promotional].freeze, T::Array[Symbol])

    # Transactional messages are often legally required (privacy updates,
    # billing notifications, security alerts) and bypass all caps by default.
    DEFAULT_CAP_EXEMPT_TIERS = T.let(%i[transactional].freeze, T::Array[Symbol])

    # Registered identifiers are interpolated into the `key:value;` suppression
    # label micro-format, so they must not contain the delimiters.
    IDENTIFIER_FORMAT = T.let(/\A[a-z0-9_]+\z/, Regexp)

    # The implicit root scope: nudges registered here roll up into every page's
    # contest with no per-page declaration (see scopes_for).
    GLOBAL_SCOPE = T.let(:global, Symbol)

    # The single argument object passed to `eligibility` and `on_win` procs.
    # Procs take this one typed argument rather than loose keywords so new
    # inputs can be added here without a flag-day migration of every
    # registered lambda.
    class EligibilityCall < T::Struct
      const :coordinator, PageNudgeCoordinator
      const :user, ::User
      const :context, PageContext
    end

    # One registered nudge in one scope (a concrete page key or a broader scope
    # such as :repo or :global; see the class docs). A nudge spanning several
    # scopes registers once per scope, with the same tier each time.
    class Registration < T::Struct
      const :id, Symbol
      # The scope this nudge lives in: a concrete page key or a broader scope
      # (:repo, :org, :global). Resolved into concrete-page contests by
      # PriorityRegistry.scopes_for.
      const :page, Symbol
      # Which surface the nudge occupies (:banner, :sidebar, …) so per-surface
      # caps can be enforced. Priority itself is surface-agnostic.
      const :surface, Symbol
      const :tier, Symbol
      # Stable, autoload-independent tiebreak within a tier.
      const :order, Integer
      # The nudge's existing analytics category, reused on suppression events
      # so analytics can join `suppressed` and `visible` events per nudge
      # without taxonomy work (ADR Step 7).
      const :category, String
      # Side-effect-free predicate. Variant *assignment* is allowed; exposure
      # logging and any other side effect belongs in `on_win`.
      const :eligibility, T.proc.params(call: EligibilityCall).returns(T::Boolean)
      # Runs at most once per request, only for a contest winner that
      # confirmed render (A|B exposure logging, last_shown_at bumps, …).
      const :on_win, T.nilable(T.proc.params(call: EligibilityCall).void)
    end

    # Per-page cap configuration (ADR Step 3). All three knobs are optional;
    # a page with no configuration has no caps (current behavior preserved).
    class PageConfiguration < T::Struct
      const :key, Symbol
      # Broader scopes that roll up into this page, most-specific first; nudges
      # registered at any of them (plus the always-implicit :global) contest on
      # this page. [] = only this page's own registrations, plus :global.
      const :scopes, T::Array[Symbol], default: [].freeze
      # Page-wide ceiling for non-exempt nudges. nil = no page-wide cap.
      const :max_visible, T.nilable(Integer)
      # Optional per-surface caps. A non-exempt nudge must clear both its
      # surface cap and the page-wide cap to render.
      const :max_visible_by_surface, T::Hash[Symbol, Integer], default: {}
      # Tiers that bypass all caps on this page.
      const :cap_exempt_tiers, T::Array[Symbol], default: DEFAULT_CAP_EXEMPT_TIERS
    end

    @registrations = T.let({}, T::Hash[Symbol, T::Array[Registration]])
    @page_configurations = T.let({}, T::Hash[Symbol, PageConfiguration])
    @frozen = T.let(false, T::Boolean)

    sig do
      params(
        id: Symbol,
        page: Symbol,
        surface: Symbol,
        tier: Symbol,
        order: Integer,
        eligibility: T.proc.params(call: EligibilityCall).returns(T::Boolean),
        category: T.nilable(String),
        on_win: T.nilable(T.proc.params(call: EligibilityCall).void),
      ).void
    end
    def self.register(id:, page:, surface:, tier:, order:, eligibility:, category: nil, on_win: nil)
      raise_if_frozen!("register")

      { id: id, page: page, surface: surface }.each do |name, value|
        validate_identifier!(name, value)
      end

      unless TIERS.include?(tier)
        raise ArgumentError, "tier must be one of #{TIERS.inspect}, got #{tier.inspect}"
      end

      if registrations_for(page).any? { |registration| registration.id == id }
        raise ArgumentError, "nudge #{id.inspect} is already registered for page #{page.inspect}"
      end

      (@registrations[page] ||= []) << Registration.new(
        id: id,
        page: page,
        surface: surface,
        tier: tier,
        order: order,
        category: category || id.to_s,
        eligibility: eligibility,
        on_win: on_win,
      )
    end

    sig do
      params(
        key: Symbol,
        scopes: T::Array[Symbol],
        max_visible: T.nilable(Integer),
        max_visible_by_surface: T::Hash[Symbol, Integer],
        cap_exempt_tiers: T::Array[Symbol],
      ).void
    end
    def self.configure_page(
      key:,
      scopes: [],
      max_visible: nil,
      max_visible_by_surface: {},
      cap_exempt_tiers: DEFAULT_CAP_EXEMPT_TIERS
    )
      raise_if_frozen!("configure_page")

      validate_identifier!(:key, key)

      if scopes.include?(key)
        raise ArgumentError, "page #{key.inspect} cannot list itself in scopes:"
      end

      if @page_configurations.key?(key)
        raise ArgumentError, "page #{key.inspect} is already configured"
      end

      invalid_tiers = cap_exempt_tiers - TIERS
      unless invalid_tiers.empty?
        raise ArgumentError, "cap_exempt_tiers must be a subset of #{TIERS.inspect}, got #{invalid_tiers.inspect}"
      end

      if max_visible && max_visible.negative?
        raise ArgumentError, "max_visible must be >= 0, got #{max_visible}"
      end

      if max_visible_by_surface.values.any?(&:negative?)
        raise ArgumentError, "max_visible_by_surface values must be >= 0, got #{max_visible_by_surface.inspect}"
      end

      @page_configurations[key] = PageConfiguration.new(
        key: key,
        scopes: scopes.uniq.freeze,
        max_visible: max_visible,
        max_visible_by_surface: max_visible_by_surface.dup.freeze,
        cap_exempt_tiers: cap_exempt_tiers.dup.freeze,
      )
    end

    # ---- Read accessors ---------------------------------------------------

    # The scope chain for a concrete page, most-specific first: the page itself,
    # its declared scopes (resolved transitively), and finally the implicit
    # :global root. Cycle-safe; each scope appears once. This is the set of
    # scopes whose registrations contest on `page`.
    sig { params(page: Symbol).returns(T::Array[Symbol]) }
    def self.scopes_for(page)
      chain = T.let([], T::Array[Symbol])
      queue = T.let([page], T::Array[Symbol])

      until queue.empty?
        scope = T.must(queue.shift)
        next if chain.include?(scope)

        chain << scope
        queue.concat(@page_configurations[scope]&.scopes || [])
      end

      chain << GLOBAL_SCOPE unless chain.include?(GLOBAL_SCOPE)
      chain
    end

    # All nudges that contest on a concrete page: the union of registrations
    # across the page's scope chain, deduped by id keeping the most-specific
    # scope's registration (page over a broader scope over :global). Returns a
    # fresh array that cannot mutate the registry.
    sig { params(page: Symbol).returns(T::Array[Registration]) }
    def self.nudges_for_page(page)
      seen = T.let(Set.new, T::Set[Symbol])
      scopes_for(page).flat_map { |scope| registrations_for(scope) }
        .select { |registration| seen.add?(registration.id) }
    end

    sig { params(page: Symbol).returns(T.nilable(Integer)) }
    def self.max_visible_for(page)
      @page_configurations[page]&.max_visible
    end

    sig { params(page: Symbol).returns(T::Hash[Symbol, Integer]) }
    def self.surface_caps_for(page)
      @page_configurations[page]&.max_visible_by_surface || {}
    end

    sig { params(page: Symbol).returns(T::Array[Symbol]) }
    def self.cap_exempt_tiers_for(page)
      @page_configurations[page]&.cap_exempt_tiers || DEFAULT_CAP_EXEMPT_TIERS
    end

    # ---- Lifecycle --------------------------------------------------------

    # Called once this file finishes loading (see the bottom of the file),
    # after any canonical registrations. Validates the scope graph (so a bad
    # cross-scope collision fails at load, not mid-request) and then freezes;
    # mutation afterwards raises FrozenRegistryError.
    sig { void }
    def self.freeze!
      validate_scopes!
      @frozen = true
    end

    # Rejects a nudge id that is reachable more than once on the same concrete
    # page through its scope chain (e.g. registered at both :global and the page,
    # or at two scopes that both roll up into it). Such a collision would make
    # the nudge contest against itself, so it is a load-time error rather than a
    # silent double-count. Pages are every scope that has registrations or a
    # configuration; each is checked against its own resolved chain.
    sig { void }
    def self.validate_scopes!
      candidate_pages = (@registrations.keys + @page_configurations.keys).uniq

      candidate_pages.each do |page|
        scopes_by_id = T.let({}, T::Hash[Symbol, T::Array[Symbol]])
        scopes_for(page).each do |scope|
          registrations_for(scope).each { |registration| (scopes_by_id[registration.id] ||= []) << scope }
        end

        collisions = scopes_by_id.select { |_id, scopes| scopes.size > 1 }
        next if collisions.empty?

        detail = collisions.map { |id, scopes| "#{id.inspect} via #{scopes.inspect}" }.join("; ")
        raise ArgumentError,
          "nudge id(s) reachable more than once on page #{page.inspect}: #{detail}. " \
          "Register a cross-page nudge at a single scope (see scopes_for)."
      end
    end
    private_class_method :validate_scopes!

    # Serializes with_test_registration's save/mutate/restore on the
    # process-global registry state. Today's test harness parallelizes by
    # forking worker processes, so the lock is uncontended; it is insurance
    # against in-process threaded runners (parallelize_me!), where two
    # overlapping blocks would otherwise interleave destructively — one
    # test's ensure restoring its snapshot over another's live
    # registrations. A Monitor (reentrant) so nested blocks don't deadlock.
    TEST_REGISTRATION_MONITOR = T.let(Monitor.new, Monitor)

    # Block-scoped test registration: temporarily registers the given nudges
    # (kwargs for `register`) and pages (kwargs for `configure_page`), yields,
    # and restores the previous registry state — including the frozen flag —
    # even if the block raises. Raises outside the test environment.
    sig do
      params(
        nudges: T::Array[T::Hash[Symbol, T.untyped]],
        pages: T::Array[T::Hash[Symbol, T.untyped]],
        blk: T.proc.returns(T.untyped),
      ).returns(T.untyped)
    end
    def self.with_test_registration(nudges: [], pages: [], &blk)
      TEST_REGISTRATION_MONITOR.synchronize do
        saved_registrations = @registrations.transform_values(&:dup)
        saved_page_configurations = @page_configurations.dup
        saved_frozen = @frozen

        begin
          @frozen = false
          nudges.each { |kwargs| register(**T.unsafe(kwargs)) }
          pages.each { |kwargs| configure_page(**T.unsafe(kwargs)) }
          validate_scopes!
          @frozen = true

          blk.call
        ensure
          @registrations.replace(saved_registrations)
          @page_configurations.replace(saved_page_configurations)
          @frozen = saved_frozen
        end
      end
    end

    sig { params(page: Symbol).returns(T::Array[Registration]) }
    def self.registrations_for(page)
      @registrations[page] || []
    end
    private_class_method :registrations_for

    sig { params(name: Symbol, value: Symbol).void }
    def self.validate_identifier!(name, value)
      return if value.to_s.match?(IDENTIFIER_FORMAT)

      raise ArgumentError,
        "#{name} must match #{IDENTIFIER_FORMAT.inspect} — it is embedded in " \
        "the `key:value;`-delimited suppression label — got #{value.inspect}"
    end
    private_class_method :validate_identifier!

    sig { params(operation: String).void }
    def self.raise_if_frozen!(operation)
      return unless @frozen

      raise FrozenRegistryError,
        "PriorityRegistry##{operation} called after freeze!. The registry is " \
        "frozen when this file finishes loading; use with_test_registration " \
        "in tests."
    end
    private_class_method :raise_if_frozen!
  end
end

# Freeze the registry as soon as this file finishes loading. This is the
# replacement for a boot-time `freeze!` hook: referencing the registry from an
# initializer would autoload it — and, via the EligibilityCall struct's const
# types, PageNudgeCoordinator and User — during app boot, tripping the
# lazy-load guard (test/integration/environment_test.rb). The file instead
# loads lazily on first use (post-boot), and freezing here keeps the "frozen
# before use, mutation raises" invariant with no boot-time reference. Future
# per-page registration files are required above this line, before the freeze.
InProductTargeting::PriorityRegistry.freeze!
