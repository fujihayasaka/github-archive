# typed: true
# frozen_string_literal: true

# These configuration entries specify which repositories Dependabot has access to by default,
# based on their visibility.

# We model the configuration with the following entry:
# - dependabot.default_repository_access: determines Dependabot's visibility access to repositories in an org
module Configurable
  module DependabotDefaultRepositoryAccess
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    DEPENDABOT_DEFAULT_ACCESS_KEY = "dependabot.default_repository_access"
    DEFAULT_DEPENDABOT_REPOSITORY_ACCESS_UNSET_VALUE = "public"
    ALLOWED_VALUES = %w[public internal].freeze

    def set_dependabot_default_repository_access(access_level, actor:, force: false)
      raise ArgumentError.new("Invalid access level: #{access_level}") unless ALLOWED_VALUES.include?(access_level)

      changed = config.set!(DEPENDABOT_DEFAULT_ACCESS_KEY, access_level, actor, force)
      instrument_dependabot_default_repository_access_updated(access_level:, actor:) if changed
    end

    def clear_dependabot_default_repository_access(actor:)
      changed = config.delete(DEPENDABOT_DEFAULT_ACCESS_KEY, actor)
      if changed
        instrument_dependabot_default_repository_access_updated(
          access_level: DEFAULT_DEPENDABOT_REPOSITORY_ACCESS_UNSET_VALUE, actor:
        )
      end
    end

    def dependabot_default_repository_access
      config.get(DEPENDABOT_DEFAULT_ACCESS_KEY) || DEFAULT_DEPENDABOT_REPOSITORY_ACCESS_UNSET_VALUE
    end

    def instrument_dependabot_default_repository_access_updated(access_level:, actor:)
      GitHub.instrument(
        "dependabot_repository_access.default_access_level_updated",
        self.event_context.merge(access_level:, actor:)
      )
    end
  end
end
