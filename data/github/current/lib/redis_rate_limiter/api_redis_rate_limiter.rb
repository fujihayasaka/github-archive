# typed: true
# frozen_string_literal: true

class ApiRedisRateLimiter < RedisRateLimiter
  def initialize(key, options = {})
    super
    @distributed_redis = GitHub.rate_limiter_redis
  end

  # Increases current rate limit status for `@key` by `@amount`.
  # If max_tries is reached, tries is not incremented, but rather returned as-is.
  # Passing ban_ttl will still push expiration forward by ban_ttl seconds if max_tries is reached during this invocation.
  #
  # @return [RedisRateLimiter::Result]
  def rate_without_overage
    ban_expires_at = generate_expires_at(ban_ttl) if ban_ttl

    tries, expiration = with_circuit_breaking(action: :rate_without_overage) do
      tags = ["action:rate", "cluster:#{distributed_redis.name}"]

      with_distribution(metric: "latency", tags: tags) do
        write_shard = distributed_redis.shard_for(key).write

        RATE_WITHOUT_OVERAGE_SCRIPT.execute(
          redis: write_shard,
          keys: [key],
          argv: [amount, ttl, generate_expires_at(ttl), Time.now.to_i, ban_ttl, ban_expires_at, hard_max_tries]
        )
      end
    end

    expiration ||= generate_expires_at(ttl)
    generate_result(tries, expiration)
  end

  # Opposite of rate
  # Decrements the current rate limit status for `@key` by `@amount`.
  #
  # @return [RedisRateLimiter::Result]
  def credit
    tries, expiration = with_circuit_breaking(action: :credit) do
      tags = ["action:credit", "cluster:#{distributed_redis.name}"]

      with_distribution(metric: "latency", tags: tags) do
        write_shard = distributed_redis.shard_for(key).write

        CREDIT_SCRIPT.execute(
          redis: write_shard,
          keys: [key],
          argv: [amount, ttl, generate_expires_at(ttl), Time.now.to_i]
        )
      end
    end

    expiration ||= generate_expires_at(ttl)
    generate_result(tries, expiration)
  end

  private

  def result_key
    key.split(":").last
  end

  def metrics_prefix
    "api_redis_rate_limiter"
  end

  def with_distribution(metric:, tags:, &block)
    GitHub.dogstats.distribution_time("#{metrics_prefix}.#{metric}", tags: tags) do
      block.call
    end
  end

  RATE_WITHOUT_OVERAGE_SCRIPT = LuaScript.new(<<~LUA)
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
    local tries = 0
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
    else
      tries = tonumber(redis.call("get", rate_limit_key))
    end

    -- Now that the window is either known to already exist _or_ be freshly initialized,
    -- increment the counter (`incrby` returns a number)
    local current = tries
    local incremented = false
    if tries < max_tries then
      current = redis.call("incrby", rate_limit_key, increment_amount)
      incremented = true
    end

    -- If the caller provided a ban_ttl,
    -- and the current value meets or exceeds max_tries,
    -- and we know that this was the increment that caused the counter
    -- to exceed max_tries (supporting increment amounts greater than 1),
    -- then we ban the key for the ban_ttl duration.
    if ban_expires_at and incremented and current >= max_tries and ((current - increment_amount) < max_tries) then
      redis.call("expireat", rate_limit_key, (ban_expires_at + 1))
      redis.call("setex", expires_at_key, (ban_ttl + 1), ban_expires_at)
      expires_at = ban_expires_at
    end

    return { current, expires_at }
  LUA

  CREDIT_SCRIPT = LuaScript.new(<<~LUA)
    -- rename the inputs for clarity below
    local rate_limit_key = KEYS[1]
    local increment_amount = tonumber(ARGV[1])
    local rate_limit_ttl = tonumber(ARGV[2])
    local next_expires_at = tonumber(ARGV[3])
    local current_time = tonumber(ARGV[4])
    local expires_at_key = rate_limit_key .. ":exp"

    local expires_at = tonumber(redis.call("get", expires_at_key))
    local tries = 0
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
    else
      tries = tonumber(redis.call("get", rate_limit_key))
    end

    local current = tries
    if tries > 0 then
      current = redis.call("decrby", rate_limit_key, increment_amount)
    end

    return { current, expires_at }
  LUA
end
