# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsAllowedByOwner
    KEY = "actions_allowed_by_owner".freeze

    def allow_actions(actor:)
      config.enable(KEY, actor)
    end

    def disallow_actions(actor:)
      config.disable(KEY, actor)
    end

    # used for testing
    def clear_actions_allowed(actor:)
      config.delete(KEY, actor)
    end

    # This means that the setting has to be explicitly set to `true` in order to
    # be considered enabled. `nil` is equivalent to `false`. Inherited values are ignored.
    def actions_allowed_by_owner?
      !!config.local?(KEY) && config.enabled?(KEY)
    end
  end
end
