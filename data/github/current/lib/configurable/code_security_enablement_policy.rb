# typed: true
# frozen_string_literal: true

# These configuration entries specifies whether repository admins are allowed
# to enable GitHub Code Security.

# We model the configuration with the following entry:
# - code_security.allow_repo_admin_enablement: determines whether repo admins can enable/disable Code Security
module Configurable
  module CodeSecurityEnablementPolicy
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    # This key represents the value that determines whether repo admins can enable/disable Code Security
    ALLOW_REPO_ADMIN_ENABLEMENT_KEY = "code_security.allow_repo_admin_enablement"

    def allow_repo_admins_to_modify_code_security_enablement(actor:)
      changed = config.enable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_code_security_repo_admin_enablement_entity(new_policy: "enabled", actor: actor) if changed
    end

    def disallow_repo_admins_to_modify_code_security_enablement(actor:)
      changed = config.disable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_code_security_repo_admin_enablement_entity(new_policy: "disabled", actor: actor) if changed
    end

    def repo_admins_can_modify_code_security_enablement?
      T.bind(self, Business)
      # Delegate to the old Advanced Security policy if the new policy has not been explicitly set.
      return repo_admins_can_modify_advanced_security_enablement? unless config.local?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY)
      config.enabled?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY)
    end

    private

    def instrument_code_security_repo_admin_enablement_entity(new_policy:, actor:)
      instrument "code_security_enablement_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
