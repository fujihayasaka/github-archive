# typed: strict
# frozen_string_literal: true

# Manage Copilot coding agent trigger actor policy for an organization.
# By default, only users with write access (write, maintain, or admin) can
# trigger event-based automations. This setting controls whether repositories
# can individually allow read-access users to trigger automations.
#
# Supports two states:
# - true  (let repos decide) — repositories can individually allow read-access
#                               users to trigger automations
# - false / nil (disabled, default) — only write-access users can trigger
#                                      automations across all repositories
#
# Currently included by Organization.
module Configurable
  module CopilotSweAgentTriggerActorPolicy
    extend T::Helpers

    requires_ancestor { Configurable }

    ALLOW_READ_ACCESS_TRIGGERS_KEY = "copilot_swe_agent_allow_read_access_triggers"

    # Returns whether read-access triggers are allowed at the org level.
    # false when no policy has been set (default is write-only).
    sig { returns(T::Boolean) }
    def copilot_swe_agent_allow_read_access_triggers_policy
      config.raw(ALLOW_READ_ACCESS_TRIGGERS_KEY) == "true"
    end

    # Persist the policy. Only writes the key when enabling so the config_blob
    # only carries non-default state; disabling deletes the key.
    sig { params(value: T::Boolean, actor: User).void }
    def update_copilot_swe_agent_allow_read_access_triggers(value:, actor:)
      if value
        config.set!(ALLOW_READ_ACCESS_TRIGGERS_KEY, "true", actor)
      else
        config.delete(ALLOW_READ_ACCESS_TRIGGERS_KEY, actor)
      end
    end
  end
end
