# typed: strict
# frozen_string_literal: true

# Caches the per-customer result of "does this customer have a Copilot multi-user
# budget?" so the TBB setup budget banner doesn't make billing-platform API calls
# on every enterprise/org page render.
#
# The cached value is a tri-state Symbol:
#   HAS_BUDGET   - a budget exists (callers treat this as a positive result)
#   NO_BUDGET    - every pricing target was checked and none had a budget
#   UNDETERMINED - at least one billing-platform request failed; treated as
#                  "no budget" but cached only briefly so an outage self-heals
#
# Confirmed results (HAS_BUDGET / NO_BUDGET) are cached for CACHE_TTL. Undetermined
# results are cached for the shorter ERROR_CACHE_TTL so a billing-platform outage
# stays cheap without pinning a possibly-wrong "no budget" answer for an hour.
class Billing::Cache::CopilotMultiUserBudgetClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: String } }
  SourceValueType = type_member { { fixed: Symbol } }

  HAS_BUDGET = T.let(:has_budget, Symbol)
  NO_BUDGET = T.let(:no_budget, Symbol)
  UNDETERMINED = T.let(:undetermined, Symbol)

  # How long to cache a *confirmed* budget-existence result. The banner is a
  # non-critical nudge, so a stale result (up to 1 hour) is acceptable.
  CACHE_TTL = T.let(12.hours, ActiveSupport::Duration)

  # How long to cache an *undetermined* result (a billing-platform request
  # failed). We still cache during an outage so we don't make failing API calls
  # on every render, but keep the TTL short so a possibly-incorrect "no budget"
  # answer self-heals quickly once billing-platform recovers.
  ERROR_CACHE_TTL = T.let(5.minutes, ActiveSupport::Duration)

  sig { params(customer_id: String).void }
  def initialize(customer_id)
    @customer_id = customer_id
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :copilot_multi_user_budget
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "v1:customer_id:#{source_key}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [@customer_id]
  end

  # Undetermined results use the short ERROR_CACHE_TTL so they self-heal quickly;
  # confirmed results use the full CACHE_TTL. This implementation always returns a
  # proc, so the return type is narrowed from the framework's
  # `T.any(proc, Integer)` to just the proc for more precise call sites.
  sig { override.returns(T.proc.params(arg0: SourceValueType).returns(Integer)) }
  def ttl
    T.let(
      ->(value) { value == UNDETERMINED ? ERROR_CACHE_TTL.to_i : CACHE_TTL.to_i },
      T.proc.params(arg0: Symbol).returns(Integer),
    )
  end

  # Caching is always on. The framework provides a per-cache-key-name kill switch
  # via the remote_cache_disable_for_cache_key_name feature flag.
  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(SourceValueType) }
  def fallback
    NO_BUDGET
  end

  # Billing-platform failures are surfaced as a value (UNDETERMINED), not raised,
  # so there are no error types for the framework to gracefully degrade.
  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    []
  end

  sig { override.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
  def serializer
    GitHub::RemoteCache::SymbolSerializer
  end

  # Return cached values directly (the latency win); base telemetry keeps overhead
  # low for this hot, render-time path.
  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    GitHub::RemoteCache::PrimitiveValueStalenessObserver
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Billing::Cache.client
  end
end
