# typed: strict
# frozen_string_literal: true

require "hiredis-client"
require_relative "remote_cache/client"
require_relative "remote_cache/client_factory"
require_relative "remote_cache/comparison"
require_relative "remote_cache/compressor"
require_relative "remote_cache/serializer"
require_relative "remote_cache/preset"
require_relative "remote_cache/message_pack_zstd_compressor"
require_relative "remote_cache/numeric_serializer"
require_relative "remote_cache/numeric_array_serializer"
require_relative "remote_cache/numeric_set_serializer"
require_relative "remote_cache/rounded_numeric_serializer"
require_relative "remote_cache/store"

module GitHub
  module RemoteCache
    FEATURE_FLAGS_TO_PRELOAD = [
      # long-lived
      :remote_cache,
      :remote_cache_return_source_value_with_extended_telemetry_for_cache_key_name,
      :remote_cache_disable_for_cache_key_name,

      # temporary
      :remote_cache_redis_ping,
      :remote_cache_redis_ping_connected,
      :remote_cache_global_cache,
      :remote_cache_global_cache_namespaces,
    ]

    class << self
      # Creates a new RemoteCache::Client instance using a Redis store or an in-memory store.
      # The Redis store is used in production, while the in-memory store is used in tests.
      sig { params(namespace: String).returns(RemoteCache::Client) }
      def create(namespace:)
        preload_feature_flags

        store = case GitHub.remote_cache_mode
        when :remote
          # "remote_cache" is the main feature flag for enabling/disabling the remote cache
          # globally in production, across all usage.
          #
          # If this flag is not enabled, then we create a RemoteCache instance with a nil store.
          # This will cause store_configured? to return false, which will prevent the cache from
          # being used in methods like #invalidate and #fetch, and the
          # source of truth will be used directly.
          #
          # The flag can be enabled/disabled either fully, or for a % of app workers (unicorn workers,
          # job workers, stream processors) to gradually enable/disable remote cache.
          app_worker_actor = GitHub::VexiAppWorker.new(GitHub.app_worker_id)
          return Client.new(nil) if !FeatureFlag.vexi.enabled?(:remote_cache, app_worker_actor, default: true)

          use_test_cluster = should_use_test_cluster?(namespace)

          if redis = build_redis(use_test_cluster)
            GitHub::RemoteCache::Store.new(
              namespace: namespace,
              redis: redis,
              using_test_cluster: use_test_cluster
            )
          end
        when :memory
          GitHub::RemoteCache::Store.new(
            namespace: namespace,
            redis: GitHub::MemoryRedis.new
          )
        else
          nil
        end

        Client.new(store)
      rescue => e # rubocop:todo Lint/RescueException
        tags = ["namespace:#{namespace}", "error:#{e.class.name}"]
        tags << "error_cause:#{e.cause.class.name}" if e.cause
        GitHub.dogstats.increment("github.remote_cache.create.error", tags: tags)
        Client.new(nil)
      end

      sig { params(use_test_cluster: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def redis_config(use_test_cluster = true)
        if use_test_cluster
          @redis_config_test_cluster ||= T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
          @redis_config_test_cluster&.dup&.freeze
        else
          @redis_config ||= T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
          @redis_config&.dup&.freeze
        end
      end

      sig { params(use_test_cluster: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def redis_base_config(use_test_cluster = true)
        if use_test_cluster
          return @redis_base_config_test_cluster if defined?(@redis_base_config_test_cluster)

          @redis_base_config_test_cluster = T.let(GitHub.read_redis_config("config/redis_mysql.yml"), T.nilable(T::Hash[Symbol, T.untyped]))
        else
          return @redis_base_config if defined?(@redis_base_config)

          @redis_base_config = T.let(GitHub.read_redis_config("config/redis_global_cache.yml"), T.nilable(T::Hash[Symbol, T.untyped]))
        end
      end

      sig { void }
      def clear
        return unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

        use_test_cluster = should_use_test_cluster?(nil)
        redis = build_redis(use_test_cluster)
        redis.flushdb

        GH.context.reset_remote_cache_registry
      end

      private

      sig { void }
      def preload_feature_flags
        FeatureFlag.vexi.preload(FEATURE_FLAGS_TO_PRELOAD, instrumentation_properties: { "code.namespace": "remote_cache" })
      end

      sig { params(namespace: T.nilable(String)).returns(T::Boolean) }
      def should_use_test_cluster?(namespace)
        app_worker_id = GitHub.app_worker_id
        app_worker_actor = GitHub::VexiAppWorker.new(app_worker_id)
        namespace_actor = "namespace:#{namespace}" if namespace

        !FeatureFlag.vexi.enabled?(:remote_cache_global_cache, app_worker_actor, default: false) ||
        (!namespace_actor.nil? && !FeatureFlag.vexi.enabled?(:remote_cache_global_cache_namespaces, namespace_actor, default: false))
      end

      sig { params(use_test_cluster: T::Boolean).returns(::Redis) }
      def build_redis(use_test_cluster = true)
        new_redis_config = T.must(redis_base_config(use_test_cluster)).dup

        if use_test_cluster
          needs_connect = @redis_test_cluster.nil? || @redis_config_test_cluster.nil? || @redis_config_test_cluster != new_redis_config

          if needs_connect
            @redis_test_cluster&.close
            @redis_config_test_cluster = T.let(new_redis_config, T.nilable(T::Hash[Symbol, T.untyped]))
            @redis_test_cluster = T.let(::Redis.new(@redis_config_test_cluster), T.nilable(::Redis))
          end

          T.must(@redis_test_cluster)
        else
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
end
