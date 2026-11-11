# typed: true
# frozen_string_literal: true

# Public: The Api::RateLimitConfiguration manages the rate limit rules, and the
# ApiRedisRateLimiter manages the live rate limit cache; the Api::Throttler provides the
# glue between them. The Api::Throttler uses the Api::RateLimitConfiguration to
# check/update the live rate limit using the ApiRedisRateLimiter.
class Api::ConfigThrottler < Api::Throttler
  # Public: Initialize a Throttler.
  #
  # config  - The Api::RateLimitConfiguration describing the rate limit rules
  #           for a specific API consumer and resource family.
  def initialize(config, options = {})
    @rate_limit_configuration = config
    # A version for the key
    @version = 3
    key = "api_count:%d:%s:%s" % [
      @version,
      @rate_limit_configuration.family,
      @rate_limit_configuration.key]

    options = options.reverse_merge({
      runway: @rate_limit_configuration.runway,
      max_tries: @rate_limit_configuration.limit,
      ttl: @rate_limit_configuration.duration,
      family: @rate_limit_configuration.family,
    })

    super(key, options)
  end

  def inspect
    %(#<#{self.class} version=#{@version} #{check.inspect} #{options.inspect}>)
  end
end
