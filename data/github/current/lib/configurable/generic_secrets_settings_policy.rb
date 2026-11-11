# typed: strict
# frozen_string_literal: true

# These configuration entries specifies whether repository admins are allowed
# to enable/disable Secret Scanning Generic Secrets.

# We model the configuration with the following entry:
# - generic_secrets.allow_repo_admin_settings: determines whether repo admins can enable/disable Generic Secrets
module Configurable
  module GenericSecretsSettingsPolicy
    extend T::Helpers

    requires_ancestor { Configurable }

    # This key represents the value that determines whether repo admins can enable/disable Generic Secrets
    ALLOW_REPO_ADMIN_SETTINGS_KEY = "generic_secrets.allow_repo_admin_settings"

    sig { params(actor: User).returns(T.nilable(T::Boolean)) }
    def allow_repo_admins_to_modify_generic_secrets_settings(actor:)
      changed = config.enable(ALLOW_REPO_ADMIN_SETTINGS_KEY, actor)
      instrument_generic_secrets_repo_admin_settings_entity(new_policy: "enabled", actor: actor) if changed
    end

    sig { params(actor: User).returns(T.nilable(T::Boolean)) }
    def disallow_repo_admins_to_modify_generic_secrets_settings(actor:)
      changed = config.disable(ALLOW_REPO_ADMIN_SETTINGS_KEY, actor)
      instrument_generic_secrets_repo_admin_settings_entity(new_policy: "disabled", actor: actor) if changed
    end

    sig { returns(T::Boolean) }
    def repo_admins_can_modify_generic_secrets_settings?
      return true if !config.local?(ALLOW_REPO_ADMIN_SETTINGS_KEY) # default
      config.enabled?(ALLOW_REPO_ADMIN_SETTINGS_KEY)
    end

    private

    sig { params(new_policy: String, actor: User).returns(T.nilable(T::Boolean)) }
    def instrument_generic_secrets_repo_admin_settings_entity(new_policy:, actor:)
      GitHub.instrument "generic_secrets_repo_admin_settings_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
