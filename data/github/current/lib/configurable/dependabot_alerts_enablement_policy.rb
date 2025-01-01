# typed: true
# frozen_string_literal: true

# These configuration entries specify whether repository admins are allowed
# to enable/disable Dependabot alerts.

# We model the configuration with the following entry:
# - dependabot_alerts.allow_repo_admin_enablement: determines whether repo admins can enable/disable Dependabot alerts
module Configurable
  module DependabotAlertsEnablementPolicy
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    # This key represents the value that determines whether repo admins can enable/disable Dependabot alerts
    ALLOW_REPO_ADMIN_ENABLEMENT_KEY = "dependabot_alerts.allow_repo_admin_enablement"

    def allow_repo_admins_to_modify_dependabot_alerts_enablement(actor:)
      changed = config.enable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_dependabot_alerts_repo_admin_enablement_entity(new_policy: "enabled", actor: actor) if changed
    end

    def disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor:)
      changed = config.disable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_dependabot_alerts_repo_admin_enablement_entity(new_policy: "disabled", actor: actor) if changed
    end

    def repo_admins_can_modify_dependabot_alerts_enablement?
      !config.local?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY) || config.enabled?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY)
    end

    private

    def instrument_dependabot_alerts_repo_admin_enablement_entity(new_policy:, actor:)
      self.instrument "dependabot_alerts_repo_admin_enablement_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
