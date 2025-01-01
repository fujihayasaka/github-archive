# typed: true
# frozen_string_literal: true

class ApiRedisRateLimiter < RedisRateLimiter
  def initialize(key, options = {})
    super
    @distributed_redis = GitHub.rate_limiter_redis
  end

  private

  def result_key
    key.split(":").last
  end

  def metrics_prefix
    "api_redis_rate_limiter"
  end
end
