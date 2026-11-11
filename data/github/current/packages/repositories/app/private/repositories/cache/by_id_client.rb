# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::ByIdClient
    extend T::Generic

    include GitHub::RemoteCache::Preset
    include GitHub::RemoteCache::Preset::DisableIfRecentDatabaseWrite

    include Repositories::Cache::Shared

    SourceKeyType = type_member { { fixed: Integer } }
    SourceValueType = type_member { { fixed: T.nilable(IRepository) } }

    sig { returns(Integer) }
    attr_reader :id

    sig { params(id: Integer).void }
    def initialize(id)
      @id = id
    end

    sig { override.returns(Symbol) }
    def cache_key_name
      :by_id
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
      FeatureFlag.vexi.enabled?(:remote_cache_repo, actor, default: false)
    end

    sig { override.returns(SourceValueType) }
    def fallback
      nil
    end

    sig { override.returns(T.class_of(Repositories::Cache::RepositorySerializer)) }
    def serializer
      Repositories::Cache::RepositorySerializer
    end

    sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
    def staleness_observer
      Repositories::Cache::RepositoryStalenessObserver
    end

    sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
    def rollout_mode
      if FeatureFlag.vexi.enabled?(:remote_cache_repo_rollout, actor, default: false)
        GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithExtendedTelemetry
      else
        GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
      end
    end

    sig { override.returns(T::Array[T.class_of(StandardError)]) }
    def resilience_error_types
      []
    end

    private

    sig { returns(T.nilable(Repository)) }
    def actor
      return @actor if defined?(@actor)
      @actor = T.let(Repository.new(id: @id), T.nilable(Repository))
    end

    sig { override.returns(GitHub::RemoteCache::Client) }
    def cache_client
      Repositories::Cache.client
    end
  end
end
