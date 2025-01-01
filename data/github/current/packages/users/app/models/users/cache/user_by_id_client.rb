# typed: strict
# frozen_string_literal: true

class Users::Cache::UserByIdClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  CachedType = type_member { { fixed: T.nilable(User) } }

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

  sig { override.returns(String) }
  def cache_key_id
    id.to_s
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    FeatureFlag.vexi.enabled?(:users_by_id_cache_enabled, default: false)
  end

  sig { override.returns(Integer) }
  def ttl
    ((MAX_TTL_SECONDS - MIN_TTL_SECONDS) / 100.0 * FeatureFlag.vexi.percentage_of_actors_value_or_raise(:users_by_id_cache_ttl) + MIN_TTL_SECONDS).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  sig { override.returns(CachedType) }
  def fallback
    nil
  end

  sig { override.returns(T.class_of(Users::Cache::UserSerializer)) }
  def serializer
    Users::Cache::UserSerializer
  end

  sig { override.returns(T::Boolean) }
  def shadow?
    !FeatureFlag.vexi.enabled?(:users_by_id_shadow_disabled, actor, default: false)
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
