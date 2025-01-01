# typed: true
# frozen_string_literal: true

# These configuration entries specifies whether repository admins are allowed
# to enable/disable Secret Scanning.

# We model the configuration with the following entry:
# - secret_scanning.allow_repo_admin_settings: determines whether repo admins can enable/disable Secret Scanning
module Configurable
  module SecretScanningSettingsPolicy
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    # This key represents the value that determines whether repo admins can enable/disable Secret Scanning
    ALLOW_REPO_ADMIN_SETTINGS_KEY = "secret_scanning.allow_repo_admin_settings"

    def allow_repo_admins_to_modify_secret_scanning_settings(actor:)
      changed = config.enable(ALLOW_REPO_ADMIN_SETTINGS_KEY, actor)
      instrument_secret_scanning_repo_admin_settings_entity(new_policy: "enabled", actor: actor) if changed
    end

    def disallow_repo_admins_to_modify_secret_scanning_settings(actor:)
      changed = config.disable(ALLOW_REPO_ADMIN_SETTINGS_KEY, actor)
      instrument_secret_scanning_repo_admin_settings_entity(new_policy: "disabled", actor: actor) if changed
    end

    def repo_admins_can_modify_secret_scanning_settings?
      !config.local?(ALLOW_REPO_ADMIN_SETTINGS_KEY) || config.enabled?(ALLOW_REPO_ADMIN_SETTINGS_KEY)
    end

    private

    def instrument_secret_scanning_repo_admin_settings_entity(new_policy:, actor:)
      self.instrument "secret_scanning_repo_admin_settings_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
