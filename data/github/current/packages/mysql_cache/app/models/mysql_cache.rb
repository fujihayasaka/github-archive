# typed: true
# frozen_string_literal: true

class MysqlCache

  RETRYABLE_EXCEPTIONS = *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS # change to list after adding
  CONNECTION_TIMEOUT = 0.2
  TIMEOUT = 0.5
  # tcp_keepalive: 0
  # reconnect_attempts: 1
  # reconnect_delay: 0.0
  # reconnect_delay_max: 0.5
  # inherit_socket: false
  # read_timeout: 5.0
  # write_timeout: 5.0

  # DEFAULT_CONFIG = "config/redis_mysql.yml" #handle this once we know architecture cuts

  sig { returns(T.nilable(::Redis)) }
  attr_reader :redis

  # sig { returns(Resilient::CircuitBreaker) }
  # attr_reader :primary_cache_circuit_breaker

  sig { void }
  def initialize
    @redis = nil
  end

  def redis_client
    @redis ||= ::Redis.new(GitHub.read_redis_config("config/defaults/redis_mysql.yml", connect_timeout: CONNECTION_TIMEOUT))
  end

  def get(key:)
    GitHub.logger.with_named_tags({
      "code.function": "get",
      "code.namespace": self.class.name,
      "gh.mysql_cache.key": key,
    }) do
      if primary_cache_circuit_breaker.allow_request?
        GitHub.logger.info("Circuit breaker is closed, allowing request")
        begin
          primary_cache_circuit_breaker.success
          @redis.get(key)
        rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS => e
          GitHub.logger.error("Failed to get key from Redis", { exception: e })
          primary_cache_circuit_breaker.failure
          nil
        end
      else
        GitHub.logger.info("Circuit breaker is open, not allowing request")
        nil
      end
    end
  end

  # added a set_time as part of the key, however if the TTL is short its not needed
  sig do
    params(
      key_prefix: String,
      user_type: String,
      repo_id: Integer,
      set_time: Integer,
    ).returns(String)
  end
  def key(key_prefix:, user_type:, repo_id:, set_time:)
    "#{key_prefix}-#{user_type}-#{repo_id}-#{set_time}"
  end

  def set(key:, value:, expire_sec: 3)
    GitHub.logger.with_named_tags({
      "code.function": "set",
      "code.namespace": self.class.name,
      "gh.mysql_cache.key": key,
      "gh.mysql_cache.value": value,
      "gh.mysql_cache.expire_sec": expire_sec,
    }) do
      if primary_cache_circuit_breaker.allow_request?
        GitHub.logger.info("Circuit breaker is closed, allowing request")
        begin
          response = @redis.set(key, value, ex: expire_sec)
          primary_cache_circuit_breaker.success
          response
        rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS => e
          GitHub.logger.error("Failed to set key in Redis", { exception: e })
          primary_cache_circuit_breaker.failure
          false
        end
      else
        GitHub.logger.info("Circuit breaker is open, not allowing request")
        false
      end
    end
  end

  sig do
    params(
      client: String,
    ).returns(Resilient::CircuitBreaker)
  end
  def cache_circuit_breaker(client)
    Resilient::CircuitBreaker.get(client, {
        instrumenter: GitHub,
        # seconds after tripping circuit before allowing retry
        sleep_window_seconds: 3,
        # number of requests that must be made within a statistical window
        # before open/close decisions are made using stats
        request_volume_threshold: 3,
        # % of signals that must be failed to trip the circuit
        error_threshold_percentage: 50,
        # optional: number of seconds in the statistical window
        window_size_in_seconds: 15,
        # optional: size of buckets in statistical window
        bucket_size_in_seconds: 5,
    })
  end

  def primary_cache_circuit_breaker
    @primary_cache_circuit_breaker ||= cache_circuit_breaker("mysql_redis")
  end
end
