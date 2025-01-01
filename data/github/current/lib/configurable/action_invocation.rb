# typed: false
# frozen_string_literal: true

module Configurable
  module ActionInvocation
    include Instrumentation::Model

    KEY = "action_invocation_blocked".freeze
    BLOCKED_FOR_REPUTATION = "blocked_for_reputation".freeze

    # Public: Determine whether action invocation is blocked for the entity for any reason.
    #
    # Returns true when blocked.
    def action_invocation_blocked?
      # GitHub Actions is blocked if value is true or blocked_for_reputation (deprecated)
      config.enabled?(KEY) || config.get(KEY) == BLOCKED_FOR_REPUTATION
    end

    # Public: Block action invocation for the entity.
    #
    # blocking_user - The user enabling the invocation block
    #
    # Returns nothing.
    def block_action_invocation(blocking_user)
      config.enable(KEY, blocking_user)
      instrument :block, prefix: :action_invocation, staff_actor: blocking_user
    end

    # Public: Block action invocation for the entity due to its reputation score
    # Should be used for ReputationScoreChangeEvents with score of 0
    #
    # blocking_user - The user enabling the invocation block
    #
    # Returns nothing.
    def block_action_invocation_for_reputation(blocking_user)
      config.set(KEY, BLOCKED_FOR_REPUTATION, blocking_user)
      instrument :block_on_reputation, prefix: :action_invocation, staff_actor: blocking_user
    end

    # Public: Unblock action invocation for the entity.
    #
    # unblocking_user - The user disabling the invocation block
    #
    # Returns nothing.
    def unblock_action_invocation(unblocking_user)
      config.disable(KEY, unblocking_user)
      instrument :unblock, prefix: :action_invocation, staff_actor: unblocking_user
    end
  end
end
