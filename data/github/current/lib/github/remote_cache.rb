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
require_relative "remote_cache/rounded_numeric_serializer"
require_relative "remote_cache/store"

# Loading hiredis changes the default driver, which we are reverting, since all other connections
# use the ruby driver at this point.
RedisClient.default_driver = :ruby

module GitHub
  module RemoteCache
    class << self
      # Creates a new RemoteCache::Client instance using a Redis store or an in-memory store.
      # The Redis store is used in production, while the in-memory store is used in tests.
      sig { params(namespace: String).returns(RemoteCache::Client) }
      def create(namespace:)
        store = case GitHub.remote_cache_mode
        when :remote
          # "remote_cache" is the main feature flag for enabling/disabling the remote cache
          # globally in production, across all usage.
          #
          # If this flag is not enabled, then we create a RemoteCache instance with a nil store.
          # This will cause store_configured? to return false, which will prevent the cache from
          # being used in methods like #invalidate and #fetch, and the
          # source of truth will be used directly.
          return Client.new(nil) if !FeatureFlag.vexi.enabled?(:remote_cache, default: true)

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

          @redis_base_config_test_cluster = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
          @redis_base_config_test_cluster = GitHub.read_redis_config("config/redis_mysql.yml").merge({
            driver: :hiredis,
            reconnect_attempts: 0,
          })
        else
          return @redis_base_config if defined?(@redis_base_config)

          @redis_base_config = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
          @redis_base_config = GitHub.read_redis_config("config/redis_global_cache.yml").merge({
            driver: :hiredis,
            reconnect_attempts: 0,
          })
        end
      end

      # Configuration for the circuit breaker via feature flags used as "dials".
      # This will help us iterate on tweaking the circuit breaker in the first phase
      # where we're not really sure what the best values are.
      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_circuit_breaker_config
        return nil unless FeatureFlag.vexi.enabled?(:remote_cache_circuit_breaker, default: false)

        error_threshold = FeatureFlag.vexi.percentage_of_actors_value_or_raise(:remote_cache_circuit_breaker_error_threshold) * 100 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        error_threshold_timeout = FeatureFlag.vexi.percentage_of_actors_value_or_raise(:remote_cache_circuit_breaker_error_threshold_timeout) * 100 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        error_timeout = FeatureFlag.vexi.percentage_of_actors_value_or_raise(:remote_cache_circuit_breaker_error_timeout) * 100 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        success_threshold = FeatureFlag.vexi.percentage_of_actors_value_or_raise(:remote_cache_circuit_breaker_success_threshold) * 100 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

        return nil unless error_threshold > 0 && error_threshold_timeout > 0 && error_timeout > 0 && success_threshold > 0

        { error_threshold:, error_threshold_timeout:, error_timeout:, success_threshold: }
      end

      private

      sig { params(namespace: String).returns(T::Boolean) }
      def should_use_test_cluster?(namespace)
        app_worker_id = GitHub.app_worker_id
        app_worker_actor = GitHub::VexiAppWorker.new(app_worker_id)
        namespace_actor = "namespace:#{namespace}"

        !FeatureFlag.vexi.enabled?(:remote_cache_global_cache, app_worker_actor, default: false) ||
        !FeatureFlag.vexi.enabled?(:remote_cache_global_cache_namespaces, namespace_actor, default: false)
      end

      sig { params(use_test_cluster: T::Boolean).returns(::Redis) }
      def build_redis(use_test_cluster = true)
        new_redis_config = T.must(redis_base_config(use_test_cluster)).dup

        if circuit_breaker_config = self.build_circuit_breaker_config
          new_redis_config[:circuit_breaker] = circuit_breaker_config
        end

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
