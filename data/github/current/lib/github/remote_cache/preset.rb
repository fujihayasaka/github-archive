# typed: strict
# frozen_string_literal: true

module GitHub
  # High-level interface for remote caching with pre-configured settings.
  #
  # This module provides a convenient way to use remote caching by encapsulating common
  # configuration patterns. Instead of calling `GitHub::RemoteCache::Client` methods directly
  # with many parameters, you can create a preset class that defines your caching configuration
  # once and provides clean `fetch`, `fetch_multi`, `store`, and `invalidate` methods.
  #
  # Example: Single-key preset for caching repository data
  #
  #   # First, define a cache module using the ClientFactory:
  #   module Repositories
  #     module Cache
  #       extend GitHub::RemoteCache::ClientFactory
  #
  #       REMOTE_CACHE_NAMESPACE = "repositories"
  #
  #       sig { override.returns(GH::Domain::Base) }
  #       private_class_method def self.domain_instance
  #         Repositories.domain
  #       end
  #
  #       sig { override.returns(String) }
  #       private_class_method def self.namespace
  #         REMOTE_CACHE_NAMESPACE
  #       end
  #     end
  #   end
  #
  #   # Then, define your single-key preset class with a composite key:
  #   class Repositories::Cache::UserPermissionClient
  #     include GitHub::RemoteCache::Preset
  #
  #     # The source key is a tuple of `[repository_id, user_id]`
  #     # This represents the "raw parts" needed to compute the cache value
  #     SourceKeyType = type_member { { fixed: [Integer, Integer] } }
  #     SourceValueType = type_member { { fixed: Integer } }
  #
  #     sig { params(repository_id: Integer, user_id: Integer).void }
  #     def initialize(repository_id, user_id)
  #       @repository_id = repository_id
  #       @user_id = user_id
  #     end
  #
  #     sig { override.returns(Symbol) }
  #     def cache_key_name
  #       :repository_user_permission
  #     end
  #
  #     # Convert the composite source key into a cache key ID string
  #     sig { override.params(source_key: SourceKeyType).returns(String) }
  #     def cache_key_id(source_key)
  #       repo_id, user_id = source_key
  #       "repo_id:#{repo_id}:user_id:#{user_id}"
  #     end
  #
  #     # Return the raw components as a single tuple. This is what gets passed to
  #     # `cache_key_id` and to the block in `fetch_multi`
  #     sig { override.returns(T::Array[SourceKeyType]) }
  #     def source_keys
  #       [[@repository_id, @user_id]]
  #     end
  #
  #     sig { override.returns(Integer) }
  #     def ttl
  #       5.minutes.to_i
  #     end
  #
  #     sig { override.returns(T::Boolean) }
  #     def enabled?
  #       true
  #     end
  #
  #     sig { override.returns(SourceValueType) }
  #     def fallback
  #       0
  #     end
  #
  #     sig { override.returns(T::Array[T.class_of(StandardError)]) }
  #     def resilience_error_types
  #       GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  #     end
  #
  #     sig { override.returns(T.class_of(GitHub::RemoteCache::NumericSerializer)) }
  #     def serializer
  #       GitHub::RemoteCache::NumericSerializer
  #     end
  #
  #     sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  #     def rollout_mode
  #       GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
  #     end
  #
  #     sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  #     def staleness_observer
  #       GitHub::RemoteCache::PrimitiveValueStalenessObserver
  #     end
  #
  #     # Optional: pass additional context to a custom staleness observer for custom metrics.
  #     # Only useful when implementing your own StalenessObserver that handles the context.
  #     # Built-in observers like PrimitiveValueStalenessObserver do not use this.
  #     sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  #     def staleness_context
  #       { repository_id: @repository_id, user_id: @user_id }
  #     end
  #
  #     private
  #
  #     sig { override.returns(GitHub::RemoteCache::Client) }
  #     def cache_client
  #       Repositories::Cache.client
  #     end
  #   end
  #
  #   # Usage:
  #   cache = Repositories::Cache::UserPermissionClient.new(repository.id, user.id)
  #   permission = cache.fetch do
  #     # Returns an integer permission level (e.g., 0=none, 1=read, 2=write, 3=admin)
  #     repository.permission_level_for(user)
  #   end
  #
  # Example: Multi-key preset for caching repository permissions across multiple users
  #
  #   # Using the same cache module pattern:
  #   class Repositories::Cache::UserPermissionsClient
  #     include GitHub::RemoteCache::Preset
  #
  #     # Each source key is a tuple of `[repository_id, user_id]`
  #     # `source_keys` returns an array of these tuples - one per repo/user combination
  #     SourceKeyType = type_member { { fixed: [Integer, Integer] } }
  #     SourceValueType = type_member { { fixed: Integer } }
  #
  #     sig { params(repository_id: Integer, user_ids: T::Array[Integer]).void }
  #     def initialize(repository_id, user_ids)
  #       @repository_id = repository_id
  #       @user_ids = user_ids
  #     end
  #
  #     sig { override.returns(Symbol) }
  #     def cache_key_name
  #       :repository_user_permission
  #     end
  #
  #     # Convert each composite source key into a cache key ID string
  #     sig { override.params(source_key: SourceKeyType).returns(String) }
  #     def cache_key_id(source_key)
  #       repo_id, user_id = source_key
  #       "repo_id:#{repo_id}:user_id:#{user_id}"
  #     end
  #
  #     # Return one tuple per user - each is a complete source key
  #     # NOT an array of user IDs! Each element should contain ALL the raw parts
  #     # needed to compute that specific cache value
  #     sig { override.returns(T::Array[SourceKeyType]) }
  #     def source_keys
  #       @user_ids.map { |user_id| [@repository_id, user_id] }
  #     end
  #
  #     sig { override.returns(Integer) }
  #     def ttl
  #       10.minutes.to_i
  #     end
  #
  #     sig { override.returns(T::Boolean) }
  #     def enabled?
  #       true
  #     end
  #
  #     sig { override.returns(SourceValueType) }
  #     def fallback
  #       0
  #     end
  #
  #     sig { override.returns(T::Array[T.class_of(StandardError)]) }
  #     def resilience_error_types
  #       GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  #     end
  #
  #     sig { override.returns(T.class_of(GitHub::RemoteCache::NumericSerializer)) }
  #     def serializer
  #       GitHub::RemoteCache::NumericSerializer
  #     end
  #
  #     sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  #     def rollout_mode
  #       GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
  #     end
  #
  #     private
  #
  #     sig { override.returns(GitHub::RemoteCache::Client) }
  #     def cache_client
  #       Repositories::Cache.client
  #     end
  #   end
  #
  #   # Usage:
  #   cache = Repositories::Cache::UserPermissionsClient.new(repository.id, [user1_id, user2_id, user3_id])
  #
  #   # The block receives an array of `[repo_id, user_id]` tuples for cache misses
  #   # and should return a hash mapping those tuples back to their computed values
  #   permissions = cache.fetch_multi do |source_keys|
  #     user_ids = source_keys.map { |(repo_id, user_id)| user_id }
  #     permissions_by_user = RepositoryPermission
  #       .where(repository_id: repository.id, user_id: user_ids)
  #       .pluck(:user_id, :level)
  #       .to_h
  #
  #     source_keys.to_h do |(repo_id, user_id)|
  #       [[repo_id, user_id], permissions_by_user[user_id] || 0]
  #     end
  #   end
  #
  # The preset pattern provides several benefits:
  # - Cleaner, more readable code at call sites
  # - Centralized cache configuration
  # - Type safety with generic type members
  # - Easier testing and mocking
  # - Consistent caching behavior across the codebase
  module RemoteCache::Preset
    extend T::Helpers
    extend T::Generic
    abstract!

    SourceKeyType = type_member
    SourceValueType = type_member

    # Fetches a single value from cache or computes it using the provided block.
    #
    # @param force_refresh [Boolean] If true, bypasses the cache read, computes the value via the block, and stores it in the cache
    # @param graceful_degradation [Boolean] If true, catches errors from `resilience_error_types` during block execution and returns `fallback` value; if false, errors from the block are not handled
    # @param block [Proc] Block that computes the value if not cached
    # @return [SourceValueType] The cached or computed value
    sig(:final) do
      params(
        force_refresh: T::Boolean,
        graceful_degradation: T::Boolean,
        block: T.proc.returns(SourceValueType)
      ).returns(SourceValueType)
    end
    def fetch(force_refresh: false, graceful_degradation: true, &block)
      cache_key_id = build_cache_key_id(T.must(source_keys.first))

      cache_client.fetch(
        cache_key_name: cache_key_name,
        cache_key_id: cache_key_id,
        ttl: ttl,
        enabled: _internal_enabled?,
        fallback: fallback,
        resilience_error_types: graceful_degradation ? resilience_error_types : [],
        serializer: serializer,
        staleness_observer: staleness_observer,
        staleness_context: include_observer_context? ? staleness_context : nil,
        cache_read_observer: cache_read_observer,
        cache_read_context: include_observer_context? ? cache_read_context : nil,
        rollout_mode: rollout_mode,
        force_refresh: force_refresh,
        &block
      )
    end

    # Fetches multiple values from cache or computes them using the provided block.
    #
    # The block receives an array of source keys that need to be computed and should return
    # a hash mapping those source keys to their values.
    #
    # @param force_refresh [Boolean] If true, bypasses the cache read, computes values via the block, and stores them in the cache
    # @param graceful_degradation [Boolean] If true, catches errors from `resilience_error_types` during block execution and returns `fallback` value for all keys; if false, errors from the block are not handled
    # @param block [Proc] Block that computes values for the given source keys
    # @return [Hash<SourceKeyType, SourceValueType>] Hash mapping source keys to their cached or computed values
    sig(:final) do
      params(
        force_refresh: T::Boolean,
        graceful_degradation: T::Boolean,
        block: T.proc.params(source_keys: T::Array[SourceKeyType]).returns(T::Hash[SourceKeyType, SourceValueType])
      ).returns(T::Hash[SourceKeyType, T.nilable(SourceValueType)])
    end
    def fetch_multi(force_refresh: false, graceful_degradation: true, &block)
      source_to_cache_key_ids = build_cache_key_id_map
      cache_to_source_key_ids = source_to_cache_key_ids.invert
      cache_key_ids = source_to_cache_key_ids.values

      results = cache_client.fetch_multi(
        cache_key_name: cache_key_name,
        cache_key_ids: cache_key_ids,
        ttl: ttl,
        enabled: _internal_enabled?,
        fallback: fallback,
        resilience_error_types: graceful_degradation ? resilience_error_types : [],
        serializer: serializer,
        staleness_observer: staleness_observer,
        staleness_context: include_observer_context? ? staleness_context : nil,
        cache_read_observer: cache_read_observer,
        cache_read_context: include_observer_context? ? cache_read_context : nil,
        rollout_mode: rollout_mode,
        force_refresh: force_refresh
      ) do |missing_cache_key_ids|
        missing_source_keys = missing_cache_key_ids.map { |id| T.must(cache_to_source_key_ids[id]) }
        result = block.call(missing_source_keys)
        result.transform_keys { |source_key| T.must(source_to_cache_key_ids[source_key]) }
      end

      results.transform_keys { |key_id| T.must(cache_to_source_key_ids[key_id]) }
    end

    # Stores a value directly in the cache without computing it.
    #
    # This is useful for proactively caching values that you've already computed.
    #
    # @param value [SourceValueType] The value to store in the cache
    sig(:final) { params(value: SourceValueType).void }
    def store(value)
      cache_key_id = build_cache_key_id(T.must(source_keys.first))

      cache_client.store(
        cache_key_name: cache_key_name,
        cache_key_id: cache_key_id,
        value: value,
        ttl: ttl,
        enabled: _internal_enabled?,
        serializer: serializer
      )
    end

    # Invalidates cache values for the source keys.
    #
    # Automatically handles both single-key and multi-key invalidation based on the
    # number of source keys.
    #
    # @param event [String, nil] Optional event name for tracking invalidation metrics
    sig(:final) { params(event: T.nilable(String)).void }
    def invalidate(event = nil)
      keys = source_keys
      return if keys.empty?

      if keys.size == 1
        cache_client.invalidate(
          cache_key_name: cache_key_name,
          cache_key_id: build_cache_key_id(T.must(keys.first)),
          event: event
        )
      else
        cache_key_ids = build_cache_key_id_map(keys).values

        cache_client.invalidate_multi(
          cache_key_name: cache_key_name,
          cache_key_ids: cache_key_ids,
          event: event
        )
      end
    end

    sig { returns(T::Array[String]) }
    def base_metric_tags
      cache_client.base_metric_tags
    end

    sig { abstract.returns(Symbol) }
    def cache_key_name; end

    sig { abstract.params(source_key: SourceKeyType).returns(String) }
    def cache_key_id(source_key); end

    sig { abstract.returns(T.any(T.proc.params(value: SourceValueType).returns(Integer), Integer)) }
    def ttl; end

    sig { abstract.returns(T::Boolean) }
    def enabled?; end

    # how to handle nilable as an option?
    sig { abstract.returns(SourceValueType) }
    def fallback; end

    sig { abstract.returns(T::Array[T.class_of(StandardError)]) }
    def resilience_error_types; end

    sig { abstract.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
    def serializer; end

    sig { abstract.returns(GitHub::RemoteCache::Client::RolloutMode) }
    def rollout_mode; end

    sig { abstract.returns(T::Array[SourceKeyType]) }
    def source_keys; end

    sig { overridable.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def staleness_context; end

    sig { abstract.returns(T.nilable(GitHub::RemoteCache::StalenessObserver[SourceValueType])) }
    def staleness_observer; end

    sig { overridable.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def cache_read_context; end

    sig { overridable.returns(T.nilable(GitHub::RemoteCache::CacheReadObserver[SourceValueType])) }
    def cache_read_observer; end

    private

    sig { abstract.returns(GitHub::RemoteCache::Client) }
    def cache_client; end

    sig { returns(T::Boolean) }
    def _internal_enabled?
      enabled?
    end

    sig { params(source_key: SourceKeyType).returns(String) }
    def build_cache_key_id(source_key)
      cache_key_id(source_key)
    rescue => e
      Kernel.raise e if GitHub::ResilienceMixin.should_reraise_in_non_production?

      GitHub::RemoteCache::Client::NIL_CACHE_KEY_ID
    end

    sig { params(keys: T::Array[SourceKeyType]).returns(T::Hash[SourceKeyType, String]) }
    def build_cache_key_id_map(keys = source_keys)
      return T.must(@cache_key_id_map) if defined?(@cache_key_id_map)

      empty_hash = Hash.new(capacity: keys.size)
      @cache_key_id_map = T.let(keys.each_with_object(empty_hash) do |source_key, map|
        map[source_key] = build_cache_key_id(source_key)
      end, T.nilable(T::Hash[SourceKeyType, String]))
      T.must(@cache_key_id_map)
    end

    sig { returns(T::Boolean) }
    def include_observer_context?
      case rollout_mode
      when GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
        true
      when GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithExtendedTelemetry
        true
      when GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
        false
      end
    end
  end
end
