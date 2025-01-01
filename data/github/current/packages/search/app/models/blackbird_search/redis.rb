# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  module Redis
    extend self

    DEFAULT_KEY_PREFIX = "ar:v2"

    @sleep = true

    sig do
      params(
        key_prefix: String,
        actor_id: Integer,
        session_id: String,
      ).returns(String)
    end
    def key(key_prefix:, actor_id:, session_id:)
      "#{key_prefix}:#{actor_id}:#{session_id}"
    end

    sig do
      params(
        key: String,
        value: T.untyped,
        expire_sec: Integer, # Expire time in seconds
      ).returns(GitHub::KV::Result)
    end
    def set(key:, value:, expire_sec:)
      # https://github.com/redis/redis-rb/blob/v4.1.0/lib/redis.rb#L772-L781
      GitHub::Result.new do
        with_redis_retry { redis_instance.set(key, value, { ex: expire_sec }) } == "OK"
      end
    end

    # get returns the value of the specified key. If the key does not exist the inner value is nil.
    sig do
      params(
        key: String
      ).returns(GitHub::KV::Result)
    end
    def get(key:)
      GitHub::Result.new { with_redis_retry { redis_instance.get(key) } }
    end

    # pttl returns the remaining TTL in milliseconds for the entry at the specified key.
    # If the key does not exist, -2 is returned, and if the key exists but has no associated TTL, -1 is returned.
    sig do
      params(
        key: String
    ).returns(GitHub::KV::Result)
    end
    def pttl(key:)
      GitHub::Result.new { with_redis_retry { redis_instance.pttl(key) } }
    end

    sig do
      params(
        keys: T::Array[String]
      ).returns(GitHub::KV::Result)
    end
    def del(keys:)
      GitHub::Result.new { with_redis_retry { redis_instance.del(keys) } }
    end

    sig { params(key: String, timeout_sec: Integer).returns(GitHub::Redis::ConcurrencySafeMutex) }
    def mutex(key:, timeout_sec: 60.seconds)
      GitHub::Redis::ConcurrencySafeMutex.new(key, timeout: timeout_sec, redis: redis_instance)
    end

    sig { returns(::Redis) }
    def redis_instance
      @blackbird_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_blackbird.yml")), T.nilable(::Redis))
    end

    # Private: Executes a block and rescues transient Redis errors (i.e. Redis::TimeoutError, Redis::ConnectionError, etc.),
    # and retries the block up to a limit of 5 times with exponential backoff. If execution of the block fails after the retry limit
    # is reached, the error is raised.
    #
    # Returns the result of the block.
    def with_redis_retry
      limit = 5
      backoff = 0.05 # 50ms.
      retry_count = 0
      begin
        yield
      rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS => e
        GitHub.logger.error("error communicating with Redis in BlackbirdSearch::Redis", { error: e, retry_count: retry_count })
        Failbot.report(e)
        if retry_count < limit
          Kernel.sleep backoff + (Kernel.rand * 0.05) if @sleep # Jitter added to the current backoff value is a random number between 0 and 0.05 (50ms).
          backoff *= 2
          retry_count += 1
          retry
        else
          Kernel.raise
        end
      end
    end

    # Allow processes to override the sleep behavior used in the exponential backoff for `with_redis_retry`.
    # The default is sleep is enabled.
    def set_sleep(sleep)
      @sleep = sleep
    end
  end
end
