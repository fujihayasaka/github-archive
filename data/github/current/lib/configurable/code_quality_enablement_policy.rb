# typed: true
# frozen_string_literal: true

# These configuration entries specify whether repository admins are allowed
# to enable GitHub Code Quality.

# We model the configuration with the following entry:
# - code_quality.allow_repo_admin_enablement: determines whether repo admins can enable/disable Code Quality
module Configurable
  module CodeQualityEnablementPolicy
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    # This key represents the value that determines whether repo admins can enable/disable Code Quality
    ALLOW_REPO_ADMIN_ENABLEMENT_KEY = "code_quality.allow_repo_admin_enablement"

    def allow_repo_admins_to_modify_code_quality_enablement(actor:)
      changed = config.enable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_code_quality_repo_admin_enablement_entity(new_policy: "enabled", actor: actor) if changed
    end

    def disallow_repo_admins_to_modify_code_quality_enablement(actor:)
      changed = config.disable(ALLOW_REPO_ADMIN_ENABLEMENT_KEY, actor)
      instrument_code_quality_repo_admin_enablement_entity(new_policy: "disabled", actor: actor) if changed
    end

    def repo_admins_can_modify_code_quality_enablement?
      # Default to true if not explicitly set
      return true unless config.local?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY)
      config.enabled?(ALLOW_REPO_ADMIN_ENABLEMENT_KEY)
    end

    private

    def instrument_code_quality_repo_admin_enablement_entity(new_policy:, actor:)
      instrument "code_quality_enablement_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
