# typed: true
# frozen_string_literal: true

# Manage whether SSO lockdown is enabled for a business.
# When enabled, SSO completion is blocked for everyone except enterprise owners.
module Configurable
  module SsoLockdown
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "sso_lockdown".freeze
    ENABLE_INSTRUMENTATION_KEY  = "sso_lockdown.enable"
    DISABLE_INSTRUMENTATION_KEY = "sso_lockdown.disable"

    class SsoLockdownError < StandardError; end

    # Public: Enable SSO lockdown.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def enable_sso_lockdown(actor:)
      unless T.unsafe(self).actor_can_write_sso?(actor)
        raise SsoLockdownError.new \
          "SSO lockdown can only be enabled by an enterprise owner or a user with the write_enterprise_sso permission."
      end

      return unless config.enable!(KEY, actor)

      BusinessRevokeSsoSessionsJob.perform_later(T.unsafe(self).id)
      instrument_sso_lockdown(actor: actor, name: ENABLE_INSTRUMENTATION_KEY)
    end

    # Public: Disable SSO lockdown.
    #
    # actor - The User disabling the setting.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def disable_sso_lockdown(actor:)
      unless T.unsafe(self).actor_can_write_sso?(actor)
        raise SsoLockdownError.new \
          "SSO lockdown can only be disabled by an enterprise owner or a user with the write_enterprise_sso permission."
      end

      return unless config.delete(KEY, actor)

      instrument_sso_lockdown(actor: actor, name: DISABLE_INSTRUMENTATION_KEY)
    end

    # Public: Is SSO lockdown enabled?
    #
    # Returns Boolean.
    sig { returns(T::Boolean) }
    def sso_lockdown_enabled?
      config.enabled?(KEY)
    end

    private

    sig { params(actor: User, name: String).void }
    def instrument_sso_lockdown(actor:, name:)
      payload = {
        actor: actor,
        business: self
      }

      GitHub.instrument(name, payload)
    end
  end
end
