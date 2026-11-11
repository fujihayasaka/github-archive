# typed: strict
# frozen_string_literal: true

class SecurityProducts::Cache::RepositorySecurityCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: Integer } }
  SourceValueType = type_member { { fixed: [Integer, Integer, Integer, Integer] } }

  sig { params(repo: Repository).void }
  def initialize(repo)
    @repo = repo
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :repo_security_alert_counts
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "repo_id:#{source_key}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [@repo.id]
  end

  sig { override.returns(Integer) }
  def ttl
    [10, (FeatureFlag.vexi.percentage_of_actors_value_or_raise(:global_nav_security_count_cache_ttl) * 100).to_i].max # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    return false unless @repo.persisted?
    true
  end

  sig { override.returns(SourceValueType) }
  def fallback
    [0, 0, 0, 0]
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::NumericArraySerializer)) }
  def serializer
    GitHub::RemoteCache::NumericArraySerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    GitHub::RemoteCache::PrimitiveValueStalenessObserver
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:global_nav_security_count_cache_graduated, @repo, default: false)
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    end
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    SecurityProducts::Cache.client
  end
end
