# typed: true
# frozen_string_literal: true

module Codespaces
  class PerUserRateLimiter
    include GitHub::RateLimitable
    include GitHub::Memoizer

    def self.at_limit?(user)
      new(user: user).at_limit?
    end

    def self.increment(user)
      new(user: user).increment
    end

    def self.max_tries
      GitHub.codespaces_per_minute_rate_limit
    end

    def initialize(user:, ttl: 1.minute)
      @user = user
      @use_extended_rate_limiting = user.feature_enabled?(:codespaces_extended_rate_limiting)
      @ttl = ttl
    end

    def user_has_unlimited_access?
      user.feature_enabled?(:codespaces_automated_testing) || user.feature_enabled?(:codespaces_bypass_rate_limiting)
    end

    def at_limit?
      return false if user_has_unlimited_access?

      if @use_extended_rate_limiting && extended_ttl > 0.minutes
        return true if rate_limit_check(extended_key, { max_tries: extended_max_tries, ttl: extended_ttl }).at_limit?
      end

      rate_limit_check(key, { max_tries: self.class.max_tries, ttl: ttl }).at_limit?
    end

    # Enforce a limit on actions (creates, starts, deletions right after creating) per 10 minutes, AND per 1 minute.
    def increment
      rate_limit_increment(extended_key, { ttl: extended_ttl }).tries
      rate_limit_increment(key, { ttl: ttl }).tries
    end

    private

    attr_reader :user, :ttl

    def key
      "codespaces-rate-limit-#{user.id}"
    end

    def extended_key
      "codespaces-rate-limit-10min-#{user.id}"
    end

    memoize def extended_ttl
      Codespaces::Dials::ExtendedRateLimitDurationMinutes.new.value.minutes
    end

    memoize def extended_max_tries
      Codespaces::Dials::ExtendedRateLimitMaxOperations.new.value
    end
  end
end
