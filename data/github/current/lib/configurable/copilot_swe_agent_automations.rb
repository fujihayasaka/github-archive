# typed: strict
# frozen_string_literal: true

# Manage whether triggered (automated) Copilot cloud agent sessions are
# disabled for the configured entity. This is a kill switch that admins can
# use to stop event-driven agent sessions (custom agent triggers like
# workflow_run, interval, issues, pull_request, PR comment/review) without
# disabling user-initiated (User-to-Server) flows.
#
# The setting supports three states:
# - nil   — no policy set, defer to default / lower-level setting
# - true  — admin has explicitly disabled triggered automations
# - false — admin has explicitly allowed triggered automations
module Configurable
  module CopilotSweAgentAutomations
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "copilot_swe_agent_automations_disabled"

    # Returns the explicit policy value or nil when no policy has been set.
    sig { returns(T.nilable(T::Boolean)) }
    def copilot_swe_agent_automations_disabled_policy
      raw = config.raw(KEY)
      return nil if raw.nil?

      raw == "true"
    end

    # Convenience: true iff the entity has explicitly disabled triggered
    # automations. Returns false when no policy is set.
    sig { returns(T::Boolean) }
    def copilot_swe_agent_automations_disabled?
      copilot_swe_agent_automations_disabled_policy == true
    end

    # Set, clear, or unset the policy. Pass nil to remove the policy.
    #
    # The 4th argument to `config.set!` is the entry's `final` flag, which
    # controls whether the value can be overridden by a higher-priority
    # target in the owner chain (e.g. a repository under an organization).
    # We pass `disabled` itself as that flag so:
    #
    #   - `disabled: true`  → final: true  → the restrictive value sticks
    #     and a child target (repo) cannot relax it back to allowed.
    #   - `disabled: false` → final: false → a child target may still set
    #     `true` and have it take effect, preserving "most-restrictive wins".
    sig { params(disabled: T.nilable(T::Boolean), actor: User).void }
    def update_copilot_swe_agent_automations_disabled(disabled:, actor:)
      if disabled.nil?
        config.delete(KEY, actor)
      else
        config.set!(KEY, disabled.to_s, actor, disabled)
      end
    end
  end
end
