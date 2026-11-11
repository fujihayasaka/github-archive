# typed: strict
# frozen_string_literal: true

class Users::Cache::UserByIdClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: Integer } }
  SourceValueType = type_member { { fixed: T.nilable(User) } }

  MAX_TTL_SECONDS = T.let(12.hours.in_seconds, Integer)
  MIN_TTL_SECONDS = 5

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
    ((MAX_TTL_SECONDS - MIN_TTL_SECONDS) / 100.0 * FeatureFlag.vexi.percentage_of_actors_value_or_raise(:users_by_id_cache_ttl) + MIN_TTL_SECONDS).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  sig { override.returns(SourceValueType) }
  def fallback
    nil
  end

  sig { override.returns(T.class_of(Users::Cache::UserSerializer)) }
  def serializer
    Users::Cache::UserSerializer
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    return GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry if rand(100) < ENV["USERS_BY_ID_SHADOW_PERCENTAGE"].to_i

    if FeatureFlag.vexi.enabled?(:users_by_id_shadow_disabled, actor, default: false)
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    end
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resiliency_error_types
    []
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Users::Cache.client
  end
end
