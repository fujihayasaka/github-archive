# typed: strict
# frozen_string_literal: true

# Manage Copilot coding agent trigger actor policy for a repository.
# By default, only users with write access (write, maintain, or admin) can
# trigger event-based automations. This setting controls whether a repository
# admin permits read-access users to trigger automations, subject to the
# org-level policy under "least permissive wins" (the org-level setting can
# still override and enforce write-only across all repos).
#
# Supports two states:
# - true  (allow read-level triggers) — the repo permits read-access users
#                                       to trigger automations, contingent
#                                       on the org-level policy also allowing
#                                       it and on the agent YAML not
#                                       requiring write access
# - false / nil (default) — only write-access users can trigger automations
#                           in this repo
#
# Currently included by Repository.
module Configurable
  module CopilotSweAgentRepoTriggerActorPolicy
    extend T::Helpers

    requires_ancestor { Configurable }

    ALLOW_READ_ACCESS_TRIGGERS_KEY = "copilot_swe_agent_repo_allow_read_access_triggers"

    # Returns whether read-access triggers are allowed at the repo level.
    # false when no policy has been set (default is write-only).
    sig { returns(T::Boolean) }
    def copilot_swe_agent_repo_allow_read_access_triggers_policy
      config.raw(ALLOW_READ_ACCESS_TRIGGERS_KEY) == "true"
    end

    # Persist the policy. Only writes the key when enabling so the config_blob
    # only carries non-default state; disabling deletes the key.
    sig { params(value: T::Boolean, actor: User).void }
    def update_copilot_swe_agent_repo_allow_read_access_triggers(value:, actor:)
      if value
        config.set!(ALLOW_READ_ACCESS_TRIGGERS_KEY, "true", actor)
      else
        config.delete(ALLOW_READ_ACCESS_TRIGGERS_KEY, actor)
      end
    end
  end
end
