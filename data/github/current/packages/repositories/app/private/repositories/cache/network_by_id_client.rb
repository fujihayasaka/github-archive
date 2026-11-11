# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::NetworkByIdClient
    extend T::Generic
    include GitHub::RemoteCache::Preset

    SourceKeyType = type_member { { fixed: Integer } }
    SourceValueType = type_member { { fixed: T.nilable(IRepositoryNetwork) } }

    CachedType = type_member { { fixed: T.nilable(IRepositoryNetwork) } }
    MAX_TTL_SECONDS = T.let(12.hours.in_seconds, Integer)
    MIN_TTL_SECONDS = 5

    sig { returns(Integer) }
    attr_reader :id

    sig { params(id: Integer).void }
    def initialize(id)
      @id = id
    end

    sig { override.returns(Symbol) }
    def cache_key_name
      :network_by_id
    end

    sig { override.params(source_key: SourceKeyType).returns(String) }
    def cache_key_id(source_key)
      source_key.to_s
    end

    sig { override.returns(T::Array[SourceKeyType]) }
    def source_keys
      [@id]
    end

    sig { override.returns(Integer) }
    def ttl
      ((MAX_TTL_SECONDS - MIN_TTL_SECONDS) / 100.0 * FeatureFlag.vexi.percentage_of_actors_value_or_raise(:repos_by_id_cache_ttl) + MIN_TTL_SECONDS).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      actor = Repositories::Cache::NetworkByIdActor.new(@id)
      FeatureFlag.vexi.enabled?(:remote_cache_repo, actor, default: false)
    end

    sig { override.returns(SourceValueType) }
    def fallback
      nil
    end

    sig { override.returns(T.class_of(Repositories::Cache::RepositoryNetworkSerializer)) }
    def serializer
      Repositories::Cache::RepositoryNetworkSerializer
    end

    sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
    def rollout_mode
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
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
