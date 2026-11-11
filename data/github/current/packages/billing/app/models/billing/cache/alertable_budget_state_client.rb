# typed: strict
# frozen_string_literal: true

class Billing::Cache::AlertableBudgetStateClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  # Source key is the billing-platform customer id.
  SourceKeyType = type_member { { fixed: String } }
  # Cached value is the array of raw budget hashes from billing-platform.
  SourceValueType = type_member { { fixed: T::Array[T::Hash[T.untyped, T.untyped]] } }

  TTL = T.let(1.hour.to_i, Integer)

  sig { params(customer_id: String, feature_flag_target: T.nilable(T.any(User, Organization, Business))).void }
  def initialize(customer_id, feature_flag_target: nil)
    @customer_id = customer_id
    @feature_flag_target = T.let(feature_flag_target, T.nilable(T.any(User, Organization, Business)))
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :alertable_budget_state
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "v1:customer_id:#{source_key}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [@customer_id]
  end

  sig { override.returns(Integer) }
  def ttl
    TTL
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(SourceValueType) }
  def fallback
    []
  end

  sig { override.returns(T.class_of(Billing::Cache::AlertableBudgetStateSerializer)) }
  def serializer
    Billing::Cache::AlertableBudgetStateSerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    Billing::Cache::AlertableBudgetStateStalenessObserver
  end

  sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def staleness_context
    { customer_id: @customer_id }
  end

  # Rollout progression:
  # 1. Default: ReturnSourceValueWithExtendedTelemetry (validate correctness)
  # 2. :billing_alertable_budget_state_cache_return_cached → ReturnCacheValueWithBaseTelemetry
  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:billing_alertable_budget_state_cache_return_cached, @feature_flag_target, default: false)
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    end
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    []
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Billing::Cache.client
  end
end
