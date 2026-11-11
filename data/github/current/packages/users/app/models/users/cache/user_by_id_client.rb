# typed: strict
# frozen_string_literal: true

class Users::Cache::UserByIdClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: Integer } }
  SourceValueType = type_member { { fixed: T.nilable(User) } }

  TTL_SECONDS = 5

  sig { returns(Integer) }
  attr_reader :id

  sig { returns(T.nilable(GH::Auth::Actor)) }
  attr_reader :actor

  sig { params(id: Integer, actor: T.nilable(GH::Auth::Actor)).void }
  def initialize(id, actor: nil)
    @id = T.let(id, Integer)
    @actor = actor
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :users_by_id
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    source_key.to_s
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [@id]
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    FeatureFlag.vexi.enabled?(:users_by_id_cache_enabled, default: false)
  end

  sig { override.returns(Integer) }
  def ttl
    TTL_SECONDS
  end

  sig { override.returns(SourceValueType) }
  def fallback
    nil
  end

  sig { override.returns(T.class_of(Users::Cache::UserSerializer)) }
  def serializer
    Users::Cache::UserSerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    GitHub::RemoteCache::ApplicationRecordStalenessObserver
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    return GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry if rand(100) < ENV["USERS_BY_ID_SHADOW_PERCENTAGE"].to_i

    GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    []
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Users::Cache.client
  end
end
