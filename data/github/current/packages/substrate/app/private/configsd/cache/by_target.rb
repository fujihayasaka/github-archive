# typed: strict
# frozen_string_literal: true

# caching for both single and batch (subclassed in ByTargets) fetches of resolved configuration entries by target ownership chains
class Configsd::Cache::ByTarget
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: Configurations::RepoOwnershipChain } }
  SourceValueType = type_member { { fixed: T.nilable(Configurations::ResolvedConfigEntries) } }

  MAX_TTL_SECONDS = T.let(1.hour.in_seconds, Integer)
  MIN_TTL_SECONDS = 1

  sig { params(ownership_chains: T::Array[Configurations::RepoOwnershipChain]).void }
  def initialize(ownership_chains)
    @ownership_chains = T.let(ownership_chains, T::Array[Configurations::RepoOwnershipChain])
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :config_by_target
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "#{source_key.repo_id || 0}-#{source_key.owner_id || 0}-#{source_key.business_id || 0}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    @ownership_chains
  end

  # flag percentage of actors controls the TTL
  # 0% actors -> 1 second, 100% actors -> 1 hour
  sig { override.returns(Integer) }
  def ttl
    actor_value = begin
      FeatureFlag.vexi.percentage_of_actors_value_or_raise(:remote_cache_configs_ttl) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    rescue
      0.26 # default to 10 seconds if there's an error fetching the flag value, to avoid long TTLs due to misconfiguration
    end
    ((MAX_TTL_SECONDS - MIN_TTL_SECONDS) / 100.0 * actor_value + MIN_TTL_SECONDS).to_i
  end

  sig { override.returns(SourceValueType) }
  def fallback
    {}
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    []
  end

  sig { override.returns(T.class_of(Configsd::Cache::ByTargetSerializer)) }
  def serializer
    Configsd::Cache::ByTargetSerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    Configsd::Cache::ByTargetStalenessObserver
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    FeatureFlag.vexi.enabled?(:remote_cache_configs_single_enabled, default: false)
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:remote_cache_configs_single_shadow_mode, default: true)
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    end
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Configsd::Cache.client
  end
end
