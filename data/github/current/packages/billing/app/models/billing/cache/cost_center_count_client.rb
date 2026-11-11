# typed: strict
# frozen_string_literal: true

class Billing::Cache::CostCenterCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  # Source key is a tuple of [customer_id, state]
  SourceKeyType = type_member { { fixed: [String, String] } }
  SourceValueType = type_member { { fixed: Integer } }

  TTL = T.let(5.minutes.to_i, Integer)

  sig { params(business: T.nilable(Business), customer_id: String, state: String).void }
  def initialize(business, customer_id, state)
    @business = business
    @customer_id = customer_id
    @state = state
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :cost_center_count
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    customer_id, state = source_key
    "#{customer_id}:#{state}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [[@customer_id, @state]]
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
    -1
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::NumericSerializer)) }
  def serializer
    GitHub::RemoteCache::NumericSerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    GitHub::RemoteCache::PrimitiveValueStalenessObserver
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:billing_cost_centers_count_cache_rollout, @business, default: false)
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
