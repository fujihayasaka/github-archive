# typed: true
# frozen_string_literal: true

# These configuration entries specifies whether repository admins are allowed
# to enable GitHub Advanced Security.

# We model the configuration with the following entry:
# - advanced_security.allow_repo_admin_enablement: determines whether repo admins can enable/disable GHAS
module Configurable
  module AdvancedSecurityEnablementPolicy
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    # This key represents the value that determines whether repo admins can enable/disable GHAS
    ALLOW_REPO_ADMIN_ENABLEMENT_KEY = "advanced_security.allow_repo_admin_enablement"

    def allow_repo_admins_to_modify_advanced_security_enablement(actor:)
      changed = config.enable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_advanced_security_repo_admin_enablement_entity(new_policy: "enabled", actor: actor) if changed
    end

    def disallow_repo_admins_to_modify_advanced_security_enablement(actor:)
      changed = config.disable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_advanced_security_repo_admin_enablement_entity(new_policy: "disabled", actor: actor) if changed
    end

    def repo_admins_can_modify_advanced_security_enablement?
      !config.local?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY) || config.enabled?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY)
    end

    private

    def instrument_advanced_security_repo_admin_enablement_entity(new_policy:, actor:)
      self.instrument "advanced_security_repo_admin_enablement_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
