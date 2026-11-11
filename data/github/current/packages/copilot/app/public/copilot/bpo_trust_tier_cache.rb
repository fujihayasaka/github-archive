# typed: strict
# frozen_string_literal: true

module Copilot
  # Caches BPO (billable plan owner) trust tier per owner in process-local memory.
  #
  # Uses LruRedux::ThreadSafeCache (no TTL variant) with manual staleness check:
  # - LRU eviction at MAX_ENTRIES protects memory (~200K entries × ~100 bytes ≈ ~20MB)
  # - 20-min soft freshness: recompute from DB only when computed_at > 20 min old
  # - On recompute, compares old tier vs new tier to detect trust tier changes
  #
  # Per-worker cache: each Puma worker maintains its own cache. This means a BPO's
  # tier may be computed independently by multiple workers, but each worker only
  # recomputes every 20 min per BPO — a ~90-95% reduction vs the uncached baseline.
  #
  # Used by:
  #   - TOKEN_GENERATED handler: cache trust tier, detect changes for telemetry
  #   - GetConsumptiveUser handler (Phase 2): populate response field efficiently
  module BpoTrustTierCache
    FRESHNESS_WINDOW = T.let(20.minutes.to_i, Integer)
    CACHE_TTL = T.let(24.hours.to_i, Integer)
    MAX_ENTRIES = T.let(200_000, Integer)

    OwnerType = T.type_alias { T.any(::User, ::Organization, ::Business) }

    # TTL::ThreadSafeCache provides both LRU eviction (at MAX_ENTRIES) and a hard
    # 24h TTL ceiling. We layer a 20-min soft freshness check on top via computed_at.
    # This means entries live at most 24h (hard TTL), are refreshed every 20 min
    # (soft check), and memory is bounded by MAX_ENTRIES with LRU eviction.
    #
    # Note: this is a per-worker cache. Each Puma worker maintains its own copy,
    # so change_detected metrics may fire once per worker (not once globally) and
    # workers may briefly disagree on a BPO's tier within the freshness window.
    @cache = T.let(LruRedux::TTL::ThreadSafeCache.new(MAX_ENTRIES, CACHE_TTL), LruRedux::TTL::ThreadSafeCache)

    class << self
      # Returns the trust tier for the given owner. Serves from cache if fresh (<20 min old),
      # otherwise recomputes from DB, detects changes, and updates the cache.
      #
      # Returns [tier, changed] where changed is true if the tier transitioned since last check.
      sig { params(owner: OwnerType).returns([Integer, T::Boolean]) }
      def cached_tier_with_change_detection(owner)
        key = cache_key(owner)
        entry = @cache[key]
        changed = false

        # Fresh entry exists and is within the freshness window — return cached
        if entry && (Time.now.to_i - entry[:computed_at]) < FRESHNESS_WINDOW
          return [entry[:tier], false]
        end

        fresh_tier = TrustTiers::Tier.for_billable_owner(owner).tier

        # Detect change: only compare if we had a previous entry (stale but not evicted)
        if entry && entry[:tier] != fresh_tier
          changed = true
          GitHub.dogstats.increment(
            "copilot.bpo_trust_tier.change_detected",
            tags: [
              "old_tier:#{entry[:tier]}",
              "new_tier:#{fresh_tier}",
            ]
          )
          emit_gcu_cache_bust(owner) if FeatureFlag.vexi.enabled?(:copilot_trust_tier_recalc_emit_gcu_cache, default: false)
        end

        @cache[key] = { tier: fresh_tier, computed_at: Time.now.to_i }
        [fresh_tier, changed]
      end

      # Convenience method: returns just the tier integer.
      sig { params(owner: OwnerType).returns(Integer) }
      def cached_tier(owner)
        tier, _ = cached_tier_with_change_detection(owner)
        tier
      end

      # Invalidates the cache entry for a specific owner so the next lookup recomputes.
      sig { params(owner: OwnerType).void }
      def invalidate(owner)
        @cache.delete(cache_key(owner)) # rubocop:disable GitHub/AvoidMultisiteIncompatibleCacheUsage
      end

      # Clears the cache. Used by tests.
      sig { void }
      def reset!
        @cache.clear
      end

      # Emits a GCU cache bust event when a trust tier change is detected.
      # This notifies the Copilot limiter service to invalidate its cached
      # trust tier data for all users under the affected billing entity.
      # Because change detection is backed by a per-worker cache, this event may
      # also be emitted independently by multiple Puma workers for the same tier
      # transition and therefore may appear duplicated downstream.
      sig { params(owner: OwnerType).void }
      def emit_gcu_cache_bust(owner)
        return unless FeatureFlag.vexi.enabled?(:copilot_trust_tier_change_bust_gcu_cache, default: false)

        if owner.is_a?(::Organization)
          ::Copilot::Instrumenter.instrument_copilot_limiter_bust_cache(
            tracking_id: owner.analytics_tracking_id,
            cache_type: :ORG_CACHE,
          )
        elsif owner.is_a?(::User)
          ::Copilot::Instrumenter.instrument_copilot_limiter_bust_cache(
            tracking_id: owner.analytics_tracking_id,
            cache_type: :USER_CACHE,
          )
        else
          customer_id = resolve_customer_id(owner)
          return unless customer_id

          ::Copilot::Instrumenter.instrument_copilot_limiter_bust_cache(
            tracking_id: "",
            billable_customer_id: customer_id,
            cache_type: :USER_CACHE,
          )
        end
      end

      private

      sig { params(owner: OwnerType).returns(String) }
      def cache_key(owner)
        "#{owner.class.name}:#{owner.id}"
      end

      # Resolves the billing customer ID for a Business or Organization owner.
      sig { params(owner: T.any(::Organization, ::Business)).returns(T.nilable(Integer)) }
      def resolve_customer_id(owner)
        if owner.is_a?(::Business)
          owner.customer_id
        elsif owner.is_a?(::Organization)
          owner.business&.customer_id || owner.customer_for(:general, delegate_to_business: true)&.id
        end
      end
    end
  end
end
