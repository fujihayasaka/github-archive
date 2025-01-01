# typed: true
# frozen_string_literal: true
# Public: The Api::Throttler is a thin RedisRateLimiter wrapper that allows us to
# configure instances for use within an API endpoint. Sub-class will
# likely want to define their own key and options logic for customization.
class Api::Throttler
  attr_reader :options, :key, :limiter

  # Public: Initialize a Api::Throttler.
  #
  # args -
  #        key     - The memcache key used to define the rate limit
  #        options - Hash of `RedisRateLimiter` options for defining the limit.
  def initialize(key, options = {})
    @key = "v2:#{key}"
    @options = options
    @limiter = ApiRedisRateLimiter.new(@key, @options)
  end

  # Increases the current rate limit status for `@key` by `@amount`
  #
  # @return [RedisRateLimiter::Result]
  def rate!
    limiter.rate
  end

  # Gets the current rate limit status (number of tries and expiration)
  # without incrementing any counters
  #
  # @return [RedisRateLimiter::Result]
  def check
    limiter.check
  end

  def check_and_rate!
    limiter.rate_without_overage
  end

  def remove!
    limiter.remove
  end

  def credit!
    limiter.credit
  end
end
