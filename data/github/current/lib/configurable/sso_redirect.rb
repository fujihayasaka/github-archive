# typed: false
# frozen_string_literal: true

# Manage whether SSO redirect feature is enabled for a business.
module Configurable
  module SsoRedirect
    KEY = "sso_redirect".freeze
    ENABLE_INSTRUMENTATION_KEY  = "sso_redirect.enable"
    DISABLE_INSTRUMENTATION_KEY = "sso_redirect.disable"

    class SsoRedirectError < StandardError; end

    # Public: Enable SSO redirect.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    def enable_sso_redirect(actor:)
      unless emu_business?
        raise SsoRedirectError.new \
          "SSO redirect can only be enabled for an EMU enterprise."
      end

      unless self.owner?(actor)
        raise SsoRedirectError.new \
          "SSO redirect can only be enabled by an EMU owner."
      end

      return unless config.enable!(KEY, actor)

      instrument_sso_redirect(actor: actor, name: ENABLE_INSTRUMENTATION_KEY)
    end

    # Public: Disable SSO redirect.
    #
    # actor - The User disabling the setting.
    #
    # Returns nothing.
    def disable_sso_redirect(actor:)
      unless emu_business?
        raise SsoRedirectError.new \
          "SSO redirect can only be disabled for an EMU enterprise."
      end

      unless self.owner?(actor)
        raise SsoRedirectError.new \
          "SSO redirect can only be disabled by an EMU owner."
      end

      return unless config.delete(KEY, actor)

      instrument_sso_redirect(actor: actor, name: DISABLE_INSTRUMENTATION_KEY)
    end

    # Public: Is SSO redirect enabled?
    #
    # Returns Boolean.
    def sso_redirect_enabled?
      return false unless emu_business?
      config.enabled?(KEY)
    end

    private

    def emu_business?
      self.is_a?(Business) && self.enterprise_managed_user_enabled?
    end

    def instrument_sso_redirect(actor:, name:)
      payload = {
        actor: actor,
        business: self
      }

      GitHub.instrument(name, payload)
      GlobalInstrumenter.instrument(name, payload)
    end
  end
end
