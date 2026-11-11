# typed: true
# frozen_string_literal: true

class IncrementalBackoffRateLimiter
  DEFAULT_INTERVAL = 5 # seconds

  attr_reader :at_limit, :interval

  def self.circuit_breaker(action:)
    @circuit_breakers ||= {}
    return @circuit_breakers[action] if @circuit_breakers.key?(action)

    options = {
      # seconds after tripping circuit before allowing retry
      sleep_window_seconds: 5,
      # number of requests that must be made within a statistical window
      # before open/close decisions are made using stats
      request_volume_threshold: 5,
      # % of "marks" that must be failed to trip the circuit
      error_threshold_percentage: 50,
      # number of seconds in the statistical window
      window_size_in_seconds: 30,
      # size of buckets in statistical window
      bucket_size_in_seconds: 5,
    }

    options[:instrumenter] = GitHub if GitHub.respond_to?(:instrument)

    @circuit_breakers[action] = Resilient::CircuitBreaker.get("incremental_backoff_rate_limiter_#{action}", options)
  end

  def initialize(key, interval:)
    @key               = "rate_limit:#{key}:interval"
    @interval          = interval
    @distributed_redis = GitHub.rate_limiter_redis
  end

  alias at_limit? at_limit

  # Checks and increments the rate limiting status of the given key.
  #
  # key      - String rate limit key: "rate_limit:<hashed-client-device>:interval"
  # interval - Integer specifying the time to live in seconds.
  #
  # Returns a RateLimiter instance.
  def self.check(key, interval: DEFAULT_INTERVAL)
    new(key, interval: interval).tap(&:check)
  end

  def check
    @interval = current_interval + interval
    @at_limit = !current_interval.zero?

    write(@key, @interval)
  end

  private

  def current_interval
    return @current_interval if defined?(@current_interval)

    @current_interval = with_circuit_breaking(action: :check) do
      read_only_shard = @distributed_redis.shard_for(@key).read_only
      read_only_shard.get(@key)
    end.to_i
  end

  def write(key, interval)
    with_circuit_breaking(action: :write) do
      shard = @distributed_redis.shard_for(key).write
      shard.set(@key, interval, ex: interval)
    end
  end

  def with_circuit_breaking(action:, &block)
    breaker = self.class.circuit_breaker(action: action)

    unless breaker.allow_request?
      GitHub.dogstats.increment("redis_incremental_backoff_rate_limiter.#{action}.circuit_open")
      return 0
    end

    res = block.call
    breaker.success

    res
  rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS, ::Redis::BaseError => e
    # On Redis errors, we want to report the failure, but we fail open.
    # Users should not be impacted.
    breaker.failure
    GitHub.dogstats.increment "redis_incremental_backoff_rate_limiter.#{action}.errors", tags: ["error:#{e.class.name}"]
    Failbot.report!(e)
    0
  end
end
