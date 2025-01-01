# typed: true
# frozen_string_literal: true

# A rate limiter implementation using Redis.
# `RedisRateLimiter` doesn't implement the whole rate limiting
# algorithm. It abstracts away implementation details of increasing
# and checking rate limits.
#
# `RedisRateLimiter` requires one redis connection, @distributed_redis.
# It also implements a circuit breaker and returns a full limit when Redis is down.
#
# The expiration value for a rate limiting session is based on the current utc timestamp of the request
# and adding the TTL and is stored in Redis.
#
# @see RateLimiter, which still contains most of the fixed window algorithm logic
class RedisRateLimiter
  DEFAULT_AMOUNT = 1
  DEFAULT_MAX_TRIES = 10
  DEFAULT_TTL = 60 * 5
  DEFAULT_RUNWAY = 0
  DEFAULT_FAMILY = "no-rate-limit-family"

  attr_reader :ttl

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

    @circuit_breakers[action] = Resilient::CircuitBreaker.get("rate_limiter_#{action}", options)
  end

  def initialize(key, options = {})
    @key = key
    @ban_ttl = options[:ban_ttl]
    @amount = options[:amount] || DEFAULT_AMOUNT
    @max_tries = options[:max_tries] || DEFAULT_MAX_TRIES
    @ttl = options[:ttl] || DEFAULT_TTL
    @default_ttl = options[:default_ttl] || DEFAULT_TTL
    @distributed_redis = GitHub.monolith_rate_limiter_redis
    @runway = options[:runway] || DEFAULT_RUNWAY
    @family = options[:family] || DEFAULT_FAMILY
  end

  # Increases the current rate limit status for `@key` by `@amount`
  #
  # If ban_ttl option is passed, the first invocation of `rate` that meets or exceeds the `max_tries`
  # will push the expiration of this rate to ban_ttl seconds beyond the time of this call.
  #
  # @return [Result]
  def rate
    ban_expires_at = generate_expires_at(ban_ttl) if ban_ttl

    tries, expiration = with_circuit_breaking(action: :rate) do
      GitHub.dogstats.distribution_time("#{metrics_prefix}.latency", tags: ["action:rate", "cluster:#{distributed_redis.name}"]) do
        shard = distributed_redis.shard_for(key).write
        RATE_SCRIPT.execute(
          redis: shard,
          keys: [key],
          argv: [amount, ttl, generate_expires_at(ttl), Time.now.to_i, ban_ttl, ban_expires_at, hard_max_tries]
        )
      end
    end

    expiration ||= generate_expires_at(ttl)
    generate_result(tries, expiration)
  end

  # Gets the current rate limit status (number of tries and expiration)
  # without incrementing any counters
  #
  # @return [Result]
  def check
    tries, expiration = with_circuit_breaking(action: :check) do

      GitHub.dogstats.distribution_time("#{metrics_prefix}.latency", tags: ["action:check", "cluster:#{distributed_redis.name}"]) do
        read_only_shard = distributed_redis.shard_for(key).read_only
        CHECK_SCRIPT.execute(
          redis: read_only_shard,
          keys: [key],
          argv: [Time.now.to_i]
        )
      end
    end

    expiration ||= generate_expires_at(ttl)
    generate_result(tries, expiration)
  end

  def remove
    write_shard = distributed_redis.shard_for(key).write
    write_shard.del(key)
    write_shard.del(key + ":exp")
  end

  private

  attr_reader  :amount, :ban_ttl, :default_ttl, :distributed_redis, :family, :key, :max_tries, :runway

  # overwritten in ApiRedisRateLimiter
  alias result_key key

  class LuaScript
    attr_reader :content

    def initialize(content)
      @content = content
    end

    # Message returned by redis when `evalsha`ing a script not in cache
    NOSCRIPT = "NOSCRIPT".freeze
    private_constant :NOSCRIPT

    # Execute our script on the redis server.
    #
    # We assume the script is already in the script cache and attempt to
    # execute it by sha using `evalsha`, and only actually load it into the
    # server using `script load` if we are wrong.  This avoids every unicorn
    # creating a thundering herd of identical `script load` calls on startup.
    def execute(redis:, keys:, argv:)
      retried = false
      begin
        redis.evalsha(sha, keys, argv)
      rescue Redis::CommandError => e
        if e.message.include?(NOSCRIPT) && !retried
          raw_client(redis).script("load", content)
          retried = true
          retry
        else
          raise
        end
      end
    end

    # Need special handling for possible Redis::Namespace client to avoid
    # deprecation warning since scripts can't be namespaced.
    def raw_client(redis)
      if redis.instance_of?(Redis::Namespace)
        # execute on non-namespaced raw client
        redis.redis
      else
        redis
      end
    end

    def sha
      @sha ||= Digest::SHA1.hexdigest(content) # rubocop:disable GitHub/InsecureHashAlgorithm
      # SHA1 is the digest redis uses to identify scripts,
      # we have no choice of an alternative.
    end
  end

  # Safe way to incr + expire
  # See https://redis.io/commands/incr#pattern-rate-limiter-2
  RATE_SCRIPT = LuaScript.new(<<~LUA)
    -- rename the inputs for clarity below
    local rate_limit_key = KEYS[1]
    local increment_amount = tonumber(ARGV[1])
    local rate_limit_ttl = tonumber(ARGV[2])
    local next_expires_at = tonumber(ARGV[3])
    local current_time = tonumber(ARGV[4])
    local ban_ttl = tonumber(ARGV[5])
    local ban_expires_at = tonumber(ARGV[6])
    local max_tries = tonumber(ARGV[7])
    local expires_at_key = rate_limit_key .. ":exp"


    local expires_at = tonumber(redis.call("get", expires_at_key))
    if not expires_at or expires_at < current_time then
      -- this is either a brand new window,
      -- or this window has closed, but redis hasn't cleaned up the key yet
      -- (redis will clean it up in one more second )

      -- initialize a new rate limit window
      -- tell Redis to clean this up _one second after_ the expires-at time.
      -- that way, clock differences between Ruby and Redis won't cause data to disappear.
      -- (Redis will only clean up these keys "long after" the window has passed)
      redis.call("setex", rate_limit_key, (rate_limit_ttl + 1), 0)
      redis.call("setex", expires_at_key, (rate_limit_ttl + 1), next_expires_at)

      -- since the database was updated, return the new value
      expires_at = next_expires_at
    end

    -- Now that the window is either known to already exist _or_ be freshly initialized,
    -- increment the counter (`incrby` returns a number)
    local current = redis.call("incrby", rate_limit_key, increment_amount)

    -- If the caller provided a ban_ttl,
    -- and the current value meets or exceeds max_tries,
    -- and we know that this was the increment that caused the counter
    -- to exceed max_tries (supporting increment amounts greater than 1),
    -- then we ban the key for the ban_ttl duration.
    if ban_expires_at and current >= max_tries and ((current - increment_amount) < max_tries) then
      redis.call("expireat", rate_limit_key, (ban_expires_at + 1))
      redis.call("setex", expires_at_key, (ban_ttl + 1), ban_expires_at)
      expires_at = ban_expires_at
    end

    return { current, expires_at }
  LUA

  # Getting both the value and the expiration
  # of key as needed by our algorithm needs to be ran
  # in an atomic way, hence the script.
  CHECK_SCRIPT = LuaScript.new(<<~LUA)
    -- rename the inputs for clarity below
    local rate_limit_key = KEYS[1]
    local expires_at_key = rate_limit_key .. ":exp"
    local current_time = tonumber(ARGV[1])

    local tries = tonumber(redis.call("get", rate_limit_key))
    local expires_at = nil -- maybe overridden below

    if not tries then
      -- this client hasn't initialized a window yet
      -- let this fall through to returning {nil, nil},
      -- where the application will provide details
    else
      -- we found a number of tries, now check
      -- if this window is actually expired
      expires_at = tonumber(redis.call("get", expires_at_key))
      if not expires_at or expires_at < current_time then
        -- this window hasn't been cleaned up by Redis yet, but it has closed.
        -- (maybe it was _partly_ cleaned up, if we found `tries` but not `expires_at`)
        -- ignore the data in the database; return a fresh window instead
        tries = nil
        expires_at = nil
      end
    end

    -- Maybe {nil, nil} if the window is brand new (or expired)
    return { tries, expires_at }
  LUA

  def metrics_prefix
    "general_redis_rate_limiter"
  end

  def generate_result(tries, expiration_i)
    Result.new(
      key: result_key,
      tries: tries.to_i,
      expires_at: Time.at(expiration_i),
      max_tries: max_tries,
      runway: runway,
      family: family
    )
  end

  def generate_expires_at(ttl)
    Time.now.to_i + ttl.to_i
  end

  def hard_max_tries
    max_tries + runway
  end

  def with_circuit_breaking(action:, &block)
    breaker = self.class.circuit_breaker(action: action)

    if !breaker.allow_request?
      increment_counter(metric: "#{action}.circuit_open", tags: ["cluster:#{distributed_redis.name}"])
      return [0, nil]
    end

    increment_counter(metric: "rate_limit.total", tags: ["action:#{action}", "cluster:#{distributed_redis.name}"])

    res = block.call
    breaker.success
    res
  rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS, ::Redis::BaseError => e
    # On Redis errors, we want to report the failure, but we fail open when it comes to rate limits.
    # Users should not be impacted.
    breaker.failure

    increment_counter(metric: "rate_limit.failure", tags: ["action:#{action}", "cluster:#{distributed_redis.name}"])
    increment_counter(metric: "#{action}.errors", tags: ["error:#{e.class.name}", "cluster:#{distributed_redis.name}"])

    Failbot.report!(e)
    [0, nil]
  end

  def increment_counter(metric:, tags: [])
    return unless metric
    GitHub.dogstats.increment("#{metrics_prefix}.#{metric}", tags: tags)
  end
end
