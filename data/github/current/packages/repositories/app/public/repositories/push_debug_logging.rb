# typed: strict
# frozen_string_literal: true

module Repositories
  # Provides a helper method to check if push debug logging is enabled for GHES.
  #
  # This module enables configurable debug logging for push processing to assist
  # with debugging issues in GHES where webhooks don't fire or PRs don't update.
  #
  # Configuration (set in GHES admin environment):
  #   export ENTERPRISE_PUSH_DEBUG_LOGGING_ENABLED="true"
  #   ghe-config-apply
  #
  # The config check is cached with a 1-minute TTL.
  # Logging is only available in GHES (returns false for dotcom).
  module PushDebugLogging
    extend T::Helpers

    requires_ancestor { Kernel }

    sig { returns(T::Boolean) }
    def ghes_push_logging_enabled?
      return false unless GitHub.enterprise?

      return T.must(@debug_logging_enabled) if defined?(@debug_logging_enabled)

      @debug_logging_enabled = T.let(
        GitHub.cache.fetch(
          "push_debug_logging_enabled",
          ttl: 1.minute
        ) do
          GitHub.push_debug_logging_enabled == true
        end,
        T.nilable(T::Boolean)
      )

      @debug_logging_enabled || false
    end
  end
end
