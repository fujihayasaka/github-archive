# typed: strict
# frozen_string_literal: true

class PullRequests::Cache::ActiveReposClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  CACHE_KEY_VERSION = 1
  TTL_SECONDS = 600 # 10 minutes
  MAX_REPO_IDS = 100

  SourceKeyType = type_member { { fixed: String } }
  SourceValueType = type_member { { fixed: T::Array[Integer] } }

  sig { params(current_user: User).void }
  def initialize(current_user:)
    @current_user = current_user
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :dashboard_surface_active_repos
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    source_key
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [source_key]
  end

  sig { override.returns(Integer) }
  def ttl
    TTL_SECONDS
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(SourceValueType) }
  def fallback
    []
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
    GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    []
  end

  private

  sig { returns(String) }
  def source_key
    "v#{CACHE_KEY_VERSION}:active_repos:user_id:#{@current_user.id}"
  end

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    PullRequests::Cache.client
  end
end
