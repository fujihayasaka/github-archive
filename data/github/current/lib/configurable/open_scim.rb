# typed: false
# frozen_string_literal: true

# Manage whether Open SCIM feature is enabled for a business.
module Configurable
  module OpenSCIM
    KEY = "open_scim".freeze
    ENABLE_INSTRUMENTATION_KEY  = "business.enable_open_scim"
    DISABLE_INSTRUMENTATION_KEY = "business.disable_open_scim"

    UNSUPPORTED_ENTERPRISE_ERROR = "Open SCIM cannot be configured on this enterprise."
    ENTERPRISE_OWNER_REQUIRED_ERROR = "Open SCIM can only be configured by an enterprise administrator."
    WRITE_ENTERPRISE_SCIM_REQUIRED_ERROR = "Open SCIM can only be configured by a user with the write SCIM permission."

    class OpenSCIMError < StandardError; end

    # Public: Enable Open SCIM.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    def enable_open_scim(actor:)
      unless eligible_for_open_scim?
        raise OpenSCIMError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      unless self.actor_can_write_scim?(actor)
        raise OpenSCIMError.new WRITE_ENTERPRISE_SCIM_REQUIRED_ERROR
      end

      return unless config.enable!(KEY, actor)

      instrument_open_scim(actor: actor, name: ENABLE_INSTRUMENTATION_KEY)
    end

    # Public: Disable Open SCIM.
    #
    # actor - The User disabling the setting.
    #
    # Returns nothing.
    def disable_open_scim(actor:)
      return unless open_scim_enabled?

      unless eligible_for_open_scim?
        raise OpenSCIMError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      unless self.actor_can_write_scim?(actor)
        raise OpenSCIMError.new WRITE_ENTERPRISE_SCIM_REQUIRED_ERROR
      end

      return unless config.delete(KEY, actor)

      instrument_open_scim(actor: actor, name: DISABLE_INSTRUMENTATION_KEY)
    end

    # Public: Is Open SCIM enabled?
    #
    # Returns Boolean.
    def open_scim_enabled?
      config.enabled?(KEY)
    end

    def eligible_for_open_scim?
      return false unless self.is_a?(Business)
      return false unless self.external_provider_enabled?
      return false unless self.saml_sso_enabled?
      return true if GitHub.enterprise?
      return false unless self.enterprise_managed_user_enabled?

      true
    end

    private

    def instrument_open_scim(actor:, name:)
      payload = {
        actor: actor,
        business: self
      }

      GitHub.instrument(name, payload)
      GlobalInstrumenter.instrument(name, payload)
    end
  end
end
