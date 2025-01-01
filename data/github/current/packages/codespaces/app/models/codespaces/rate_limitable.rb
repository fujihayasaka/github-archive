# typed: true
# frozen_string_literal: true

module Codespaces
  module RateLimitable
    extend T::Helpers

    requires_ancestor { Kernel }

    class RateLimitedCommandError < Error; end

    def with_rate_limiting(user, skip_increment: false)
      # Recommendation as of implementing is to try to not include any calls that could have expected exceptions due to network calls within the rate limiting block and instead perform those after.
      # Otherwise, you could end up repeatedly hitting the failing network call without rate limiting.
      check_rate_limit!(user)
      result = yield
      Codespaces::PerUserRateLimiter.increment(user) unless skip_increment
      result
    end

    protected

    def command_name
      self.class.name.underscore
    end

    def check_rate_limit!(user)
      return unless Codespaces::PerUserRateLimiter.at_limit?(user)
      GitHub.dogstats.increment("codespaces.rate_limited", tags: ["command:#{command_name}"])
      GitHub.logger.info(
        "Codespace action blocked due to rate limiting.",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.command" => command_name,
        "gh.user.login" => user.login, # rubocop:disable GitHub/DoNotAllowLogin
      )
      raise Codespaces::RateLimitError
    end
  end
end
