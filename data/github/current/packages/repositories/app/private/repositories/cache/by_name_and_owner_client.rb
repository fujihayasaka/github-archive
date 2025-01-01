# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::ByNameAndOwnerClient
    extend T::Generic
    include GitHub::RemoteCache::Preset

    CachedType = type_member { { fixed: T.nilable(IRepository) } }
    MAX_TTL_SECONDS = T.let(12.hours.in_seconds, Integer)
    MIN_TTL_SECONDS = 5

    sig { params(name: String, owner_id: Integer).void }
    def initialize(name, owner_id)
      @name = name
      @owner_id = owner_id
    end

    sig { override.returns(Symbol) }
    def cache_key_name
      :by_name_and_owner
    end

    sig { override.returns(String) }
    def cache_key_id
      "#{@name}:#{@owner_id}"
    end

    sig { override.returns(Integer) }
    def ttl
      ((MAX_TTL_SECONDS - MIN_TTL_SECONDS) / 100.0 * FeatureFlag.vexi.percentage_of_actors_value_or_raise(:repos_by_id_cache_ttl) + MIN_TTL_SECONDS).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      return false if Repository.current_role == :writing

      FeatureFlag.vexi.enabled?(:remote_cache, default: false)
    end

    sig { override.returns(T.nilable(IRepository)) }
    def fallback
      nil
    end

    sig { override.returns(T.class_of(Repositories::Cache::RepositorySerializer)) }
    def serializer
      Repositories::Cache::RepositorySerializer
    end

    sig { override.returns(T::Boolean) }
    def shadow?
      FeatureFlag.vexi.enabled?(:remote_cache_repo_shadow, default: true)
    end

    sig { override.returns(T::Array[T.class_of(StandardError)]) }
    def resiliency_error_types
      []
    end

    private

    sig { override.returns(GitHub::RemoteCache::Client) }
    def cache_client
      Repositories::Cache.client
    end
  end
end
