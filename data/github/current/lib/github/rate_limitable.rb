# typed: strict
# frozen_string_literal: true

module GitHub::RateLimitable
  include Kernel

  private

  sig { params(key: String, options: T::Hash[Symbol, T.untyped]).returns(RedisRateLimiter::Result) }
  def rate_limit_check(key, options = {})
    limit_and_record(key, false, options)
  end

  sig { params(key: String, options: T::Hash[Symbol, T.untyped]).returns(RedisRateLimiter::Result) }
  def rate_limit_increment(key, options = {})
    limit_and_record(key, true, options)
  end

  sig { params(key: String).void }
  def remove_rate_limit_key(key)
    RedisRateLimiter.new(key).remove
  end

  # Private: check or rate the limiter, and record limit hits.
  # Internal use only.
  sig { params(key: String, increment: T::Boolean, options: T::Hash[Symbol, T.untyped]).returns(RedisRateLimiter::Result) }
  def limit_and_record(key, increment, options)
    limiter = RedisRateLimiter.new(key, options)
    result = increment ? limiter.rate : limiter.check

    increment_rate_limit_hit if result.at_limit?
    result
  end

  sig { void }
  def increment_rate_limit_hit
    klass = self.class == Class ? self : self.class
    GitHub.dogstats.increment(
      "rate_limiting.limited_request",
      tags: ["source:#{klass.name&.underscore}"]
    )
  end
end
