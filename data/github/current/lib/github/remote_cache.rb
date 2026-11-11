# typed: strict
# frozen_string_literal: true

require "hiredis-client"
require_relative "remote_cache_override"
require_relative "remote_cache/comparison"
require_relative "remote_cache/compressor"
require_relative "remote_cache/serializer"
require_relative "remote_cache/staleness_observer"
require_relative "remote_cache/cache_read_observer"
require_relative "remote_cache/application_record_staleness_observer"
require_relative "remote_cache/primitive_value_staleness_observer"
require_relative "remote_cache/rounded_numeric_staleness_observer"
require_relative "remote_cache/message_pack_zstd_compressor"
require_relative "remote_cache/numeric_serializer"
require_relative "remote_cache/numeric_array_serializer"
require_relative "remote_cache/numeric_set_serializer"
require_relative "remote_cache/symbol_serializer"
require_relative "remote_cache/store"
require_relative "remote_cache/local_store"
require_relative "remote_cache/redis_store"
require_relative "remote_cache/client"
require_relative "remote_cache/client_factory"
require_relative "remote_cache/preset"
require_relative "remote_cache/preset/disable_if_recent_database_write"

module GitHub
  module RemoteCache
    FEATURE_FLAGS_TO_PRELOAD = [
      # long-lived
      :remote_cache,
      :remote_cache_return_source_value_with_extended_telemetry_for_cache_key_name,
      :remote_cache_disable_for_cache_key_name,
      :remote_cache_disable_for_site,

      # temporary
      :remote_cache_redis_ping,
      :remote_cache_redis_ping_connected,
    ]

    class << self
      # Creates a new RemoteCache::Client instance using a stack of stores
      # chosen by the current mode.
      #
      # - `:remote` uses request-local caching in front of Redis.
      # - `:local` uses only request-local caching.
      # - `:memory` uses the same stack shape as `:remote`, but with an
      #   in-process MemoryRedis backing store for tests.
      # - `nil` disables remote caching, making the client a no-op.
      sig { params(namespace: String, override: GitHub::RemoteCacheOverride).returns(RemoteCache::Client) }
      def create(namespace:, override: GitHub::RemoteCacheOverride::None)
        return Client.new(nil, namespace: namespace) if override == GitHub::RemoteCacheOverride::Skip

        preload_feature_flags

        remote_cache_mode = GitHub.remote_cache_mode

        # The `remote_cache` feature flag only applies to the production-backed
        # cache modes (`:remote` and `:local`). If one of those modes is selected
        # but the flag is disabled, create a client with no stores so cache reads,
        # writes, and invalidations bypass the cache entirely.
        if remote_cache_flag_applicable_mode?(remote_cache_mode) && (!remote_cache_enabled? || remote_cache_disabled_for_site?)
          return Client.new(nil, namespace: namespace)
        end

        force_refresh_all = override == GitHub::RemoteCacheOverride::ForceRefresh
        Client.new(build_stores(remote_cache_mode, namespace), namespace: namespace, force_refresh_all: force_refresh_all)
      rescue => e
        tags = ["namespace:#{namespace}", "error:#{e.class.name}"]
        tags << "error_cause:#{e.cause.class.name}" if e.cause
        GitHub.dogstats.increment("github.remote_cache.create.error", tags: tags)
        Client.new([GitHub::RemoteCache::LocalStore.new], namespace: namespace)
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def redis_config
        @redis_config ||= T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
        @redis_config&.dup&.freeze
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def redis_base_config
        return @redis_base_config if defined?(@redis_base_config)

        @redis_base_config = T.let(GitHub.read_redis_config("config/redis_global_cache.yml"), T.nilable(T::Hash[Symbol, T.untyped]))
      end

      private

      sig { void }
      def preload_feature_flags
        FeatureFlag.vexi.preload(FEATURE_FLAGS_TO_PRELOAD, instrumentation_properties: { "code.namespace": "remote_cache" })
      end

      sig { params(remote_cache_mode: T.nilable(Symbol)).returns(T::Boolean) }
      def remote_cache_flag_applicable_mode?(remote_cache_mode)
        remote_cache_mode == :remote || remote_cache_mode == :local
      end

      sig { returns(T::Boolean) }
      def remote_cache_enabled?
        app_worker_actor = GitHub::VexiAppWorker.new(GitHub.app_worker_id)
        FeatureFlag.vexi.enabled?(:remote_cache, app_worker_actor, default: true)
      end

      sig { returns(T::Boolean) }
      def remote_cache_disabled_for_site?
        FeatureFlag.vexi.enabled?(:remote_cache_disable_for_site, GitHub::FlipperSite.site, default: false)
      end

      sig { params(remote_cache_mode: T.nilable(Symbol), namespace: String).returns(T::Array[GitHub::RemoteCache::Store]) }
      def build_stores(remote_cache_mode, namespace)
        store_metric_tags = ["namespace:#{namespace}"]

        case remote_cache_mode
        when :remote
          # Remote mode keeps a request-local front cache while Redis provides
          # the shared backing store.
          [
            GitHub::RemoteCache::LocalStore.new,
            GitHub::RemoteCache::RedisStore.new(redis: build_redis, extra_metric_tags: store_metric_tags),
          ]
        when :memory
          # Memory mode has the same layered behavior as remote mode, but the
          # backing store is in-process MemoryRedis rather than external Redis.
          [
            GitHub::RemoteCache::LocalStore.new,
            GitHub::RemoteCache::RedisStore.new(
              redis: GitHub::MemoryRedis.create(identifier: :remote_cache),
              extra_metric_tags: store_metric_tags,
            ),
          ]
        when :local
          [GitHub::RemoteCache::LocalStore.new]
        else
          []
        end
      end

      sig { returns(::Redis) }
      def build_redis
        new_redis_config = T.must(redis_base_config).dup
        needs_connect = @redis.nil? || @redis_config.nil? || @redis_config != new_redis_config

        if needs_connect
          @redis&.close
          @redis_config = T.let(new_redis_config, T.nilable(T::Hash[Symbol, T.untyped]))
          @redis = T.let(::Redis.new(@redis_config), T.nilable(::Redis))
        end

        T.must(@redis)
      end
    end
  end
end
