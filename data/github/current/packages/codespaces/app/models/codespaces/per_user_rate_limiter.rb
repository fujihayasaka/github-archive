# typed: true
# frozen_string_literal: true

module Codespaces
  class PerUserRateLimiter
    include GitHub::RateLimitable

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
      @ttl = ttl
    end

    def user_has_unlimited_access?
      user.feature_enabled?(:codespaces_automated_testing) || user.feature_enabled?(:codespaces_bypass_rate_limiting)
    end

    def at_limit?
      return false if user_has_unlimited_access?

      rate_limit_check(key, { max_tries: self.class.max_tries, ttl: ttl }).at_limit?
    end

    def increment
      rate_limit_increment(key, { ttl: ttl }).tries
    end

    private

    attr_reader :user, :ttl

    def key
      "codespaces-rate-limit-#{user.id}"
    end
  end
end
