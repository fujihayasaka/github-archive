# typed: strict
# frozen_string_literal: true

module ServerToServerToken
  module Redis
    extend T::Helpers
    extend self

    MAX_RETRY_ATTEMPTS = 3
    BASE_BACKOFF_SECONDS = 0.01
    MAX_BACKOFF_SECONDS = 0.25

    # a timeout to use during unicorn warmup, before we know if Redis is healthy.
    REDIS_LONG_TIMEOUT = 1 # seconds

    requires_ancestor { Kernel }

    # Public: Set the string value of a key with a required expiration.
    #
    # Wraps Redis SET with instrumentation and retries. For unconditional SET,
    # Redis returns "OK"; for conditional SET (xx), Redis returns true when
    # the key was set or false when the condition was not met.
    #
    # key   - The String key name.
    # value - The String value to store.
    # px    - The Integer expiration time in milliseconds.
    # xx    - Optional Boolean. When true, only set the key if it already
    #         exists (default: nil).
    #
    # Returns "OK" for unconditional SET, true/false for conditional SET.
    # Raises on transient Redis errors after retries are exhausted.
    sig do
      params(
        key: String,
        value: String,
        px: Integer,
        xx: T.nilable(T::Boolean)
      ).returns(T.any(String, T::Boolean))
    end
    def set(key:, value:, px:, xx: nil)
      instrument("set") do
        with_retries("set") do
          redis_instance.set(key, value, px:, xx:)
        end
      end
    end

    # Public: Get the string value of a key.
    #
    # key - The String key name.
    #
    # Returns the String value, or nil if the key does not exist.
    # Raises on transient Redis errors after retries are exhausted.
    sig { params(key: String).returns(T.nilable(String)) }
    def get(key)
      instrument("get") do
        with_retries("get") do
          redis_instance.get(key)
        end
      end
    end

    # Public: Get the values of all the given keys.
    #
    # keys - An Array of String key names.
    #
    # Returns an Array of String values (or nil for keys that do not exist).
    # Raises on transient Redis errors after retries are exhausted.
    sig { params(keys: T::Array[String]).returns(T::Array[T.nilable(String)]) }
    def mget(keys)
      instrument("mget") do
        with_retries("mget") do
          redis_instance.mget(keys)
        end
      end
    end

    # Public: Delete one or more keys.
    #
    # keys - An Array of String key names to delete.
    #
    # Returns the Integer number of keys that were deleted.
    # Raises on transient Redis errors after retries are exhausted.
    sig { params(keys: T::Array[String]).returns(Integer) }
    def del(keys)
      instrument("del") do
        with_retries("del") do
          redis_instance.del(keys)
        end
      end
    end

    # Public: Get the remaining time to live of a key in seconds.
    #
    # key - The String key name.
    #
    # Returns the Integer TTL in seconds. Returns -2 if the key does not
    # exist. Returns -1 if the key exists but has no associated expiration.
    # Raises on transient Redis errors after retries are exhausted.
    sig { params(key: String).returns(Integer) }
    def ttl(key)
      instrument("ttl") do
        with_retries("ttl") do
          redis_instance.ttl(key)
        end
      end
    end

    # Public: Remove all keys from the Redis database. Only allowed in test
    # and development environments.
    #
    # Returns the String "OK".
    #
    # Raises RuntimeError if called in production.
    sig { returns(String) }
    def flushdb
      Kernel.raise "flushdb is not allowed outside test/development" unless Rails.env.local?
      redis_instance.flushdb
    end

    # Public: Return the memoized Redis connection, creating one if needed.
    #
    # Returns a ::Redis instance.
    sig { returns(::Redis) }
    def redis_instance
      @redis ||= T.let(::Redis.new(redis_config), T.nilable(::Redis))
    end

    private

    # Internal: Load the Redis connection configuration from the authnd YAML
    # file.
    #
    # Returns a Hash of Symbol keys to untyped values.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def redis_config
      base = GitHub.read_redis_config("config/redis_authnd.yml")
      return base unless FeatureFlag.vexi.enabled?(:s2s_redis_long_timeout_on_warmup, default: true)

      if ServerToServerTokens::Domain.redis_warmed?
        GitHub.dogstats.increment("server_to_server_token.redis.load_config", tags: ["timeout:short"])
        base
      else
        # if we've not established a redis connection yet in the pitchfork thread, use a longer set of timeouts
        # to ensure enable us to establish the first connection to preserve write availability.
        GitHub.dogstats.increment("server_to_server_token.redis.load_config", tags: ["timeout:long"])
        base.merge(connect_timeout: REDIS_LONG_TIMEOUT)
      end
    end

    # Internal: Wrap a block with OTEL tracing and Datadog timing.
    #
    # method_name - The String name of the calling public method, used to
    #               name the span and distribution metric.
    # block       - A block whose return value is passed through.
    #
    # Returns the result of the block.
    sig do
      type_parameters(:T)
      .params(
        method_name: String,
        block: T.proc.returns(T.type_parameter(:T)),
      ).returns(T.type_parameter(:T))
    end
    def instrument(method_name, &block)
      GitHub.tracer.in_span("ServerToServerToken::Redis.#{method_name}") do
        GitHub.dogstats.distribution_time "server_to_server_token.redis.#{method_name}" do
          yield
        end
      end
    end

    # Internal: Execute a block with retry logic, gated behind the
    # :dotcom_s2s_redis_client_retries feature flag. When the flag is off the
    # block runs exactly once.
    #
    # Retries use exponential backoff with full jitter. Only transient Redis
    # exceptions (those in GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS) are
    # retried; permanent errors such as Redis::CommandError fail fast.
    #
    # method_name - The String name of the calling public method, used for
    #               metric tags.
    # block       - A block that performs a Redis operation.
    #
    # Returns the result of the block on success.
    # Raises the original exception after MAX_RETRY_ATTEMPTS are exhausted.
    sig do
      type_parameters(:T)
      .params(
        method_name: String,
        block: T.proc.returns(T.type_parameter(:T)),
      ).returns(T.type_parameter(:T))
    end
    def with_retries(method_name, &block)
      unless FeatureFlag.vexi.enabled?(:dotcom_s2s_redis_client_retries, default: false)
        return yield
      end

      attempt      = 1
      attempt_tags = T.let([], T::Array[String])

      begin
        attempt_tags = ["attempt:#{attempt}", "method:#{method_name}"]

        result = GitHub.dogstats.distribution_time("server_to_server_token.redis.attempt.try", tags: attempt_tags) do
          yield
        end

        if attempt > 1
          GitHub.dogstats.increment("server_to_server_token.redis.attempt.result", tags: attempt_tags + ["retryable:false"])
        end

        result
      rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS => e
        if attempt < MAX_RETRY_ATTEMPTS
          # Full jitter: sleep a random fraction of the exponential cap to
          # avoid thundering herd when multiple workers retry simultaneously.
          max_sleep = [BASE_BACKOFF_SECONDS * (2**(attempt - 1)), MAX_BACKOFF_SECONDS].min
          Kernel.sleep(Kernel.rand * max_sleep)

          attempt += 1

          tags = attempt_tags + ["retryable:true", "error_class:#{e.class.name}"]
          GitHub.dogstats.increment("server_to_server_token.redis.attempt.result", tags: tags)

          retry
        end

        GitHub.dogstats.increment("server_to_server_token.redis.retries_exceeded", tags: ["method:#{method_name}"])

        raise # re-raises the last error while keeping the stack trace
      end
    end
  end
end
