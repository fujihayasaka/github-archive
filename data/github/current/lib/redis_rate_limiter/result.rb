# typed: true
# frozen_string_literal: true

class RedisRateLimiter
  class Result
    attr_reader :key, :tries, :max_tries, :expires_at, :incremented

    def initialize(key:, tries:, max_tries:, expires_at:, runway: 0, family: nil, incremented: false)
      @key = key
      @non_prefixed_key = key.sub(/\Av[0-9]:/, "") if key
      @tries = tries
      @expires_at = expires_at.utc
      @max_tries = max_tries
      @runway = runway
      @family = family
      @incremented = incremented
    end

    alias total tries

    def at_limit?
      tries >= hard_max_tries
    end
    alias limit at_limit?

    def remaining
      return @remaining if @remaining

      if tries > runway
        @remaining = [(hard_max_tries - tries), 0].max
      else
        @remaining = max_tries
      end
    end

    # Public: Sets RateLimit HTTP headers.
    #
    # headers - hash to hold headers (or request.Env)
    #
    # Returns self
    def set_headers(headers)
      headers["X-RateLimit-Limit"]     = max_tries.to_s
      headers["X-RateLimit-Remaining"] = remaining.to_s
      headers["X-RateLimit-Reset"]     = expires_at.to_i.to_s if expires_at
      headers["X-RateLimit-Used"]      = tries.to_s
      headers["X-RateLimit-Resource"]  = family.to_s

      self
    end

    # Public: Sets RateLimit log information.
    #
    # log_data - hash to hold log data
    #
    # Returns self
    def update_logs(log_data)
      log_data.update(
        "gh.rate_limit.primary.max": max_tries,
        "gh.rate_limit.primary.remaining": remaining,
        "gh.rate_limit.primary.key": @non_prefixed_key,
        "gh.rate_limit.primary.used": tries,
        "gh.rate_limit.primary.reset": expires_at.to_i.to_s,
        "gh.rate_limit.primary.family": family,
      )

      self
    end

    # Public: Sets RateLimit Hydro information.
    #
    # hydro_context - the hash holding the current hydro context
    #
    # Returns self
    def update_hydro(hydro_context)
      hydro_context.merge!({
        rate_limit: max_tries,
        rate_limit_family: family,
        rate_limit_remaining: remaining,
        rate_limit_key: @non_prefixed_key,
      })

      self
    end

    def platform_type_name
      "RateLimit"
    end

    private

    attr_reader :runway, :family

    def hard_max_tries
      max_tries + runway
    end
  end
end
