# typed: strict
# frozen_string_literal: true

require "hiredis-client"
require_relative "remote_cache/client"
require_relative "remote_cache/client_factory"
require_relative "remote_cache/comparison"
require_relative "remote_cache/compressor"
require_relative "remote_cache/serializer"
require_relative "remote_cache/staleness_observer"
require_relative "remote_cache/cache_read_observer"
require_relative "remote_cache/application_record_staleness_observer"
require_relative "remote_cache/primitive_value_staleness_observer"
require_relative "remote_cache/rounded_numeric_staleness_observer"
require_relative "remote_cache/preset"
require_relative "remote_cache/preset/disable_if_recent_database_write"
require_relative "remote_cache/message_pack_zstd_compressor"
require_relative "remote_cache/numeric_serializer"
require_relative "remote_cache/numeric_array_serializer"
require_relative "remote_cache/numeric_set_serializer"
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
    ]

    class << self
      # Creates a new RemoteCache::Client instance using a Redis store or an in-memory store.
      # The Redis store is used in production, while the in-memory store is used in tests.
      sig { params(namespace: String, skip: T::Boolean).returns(RemoteCache::Client) }
      def create(namespace:, skip: false)
        return Client.new(nil) if skip

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

          if redis = build_redis
            GitHub::RemoteCache::Store.new(namespace: namespace, redis: redis)
          end
        when :memory
          GitHub::RemoteCache::Store.new(
            namespace: namespace,
            redis: GitHub::MemoryRedis.create(identifier: :remote_cache)
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
