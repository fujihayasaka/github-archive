# typed: false
# frozen_string_literal: true

# Manage whether Integrations are allowed to access content that is protected
# with an IP allow list maintained in IdP. If enabled, all Integration access will not be restricted,
# otherwise IdP conditional access policy will be checked to determine if the request is from a trusted source.
module Configurable
  module SkipIdpIpAllowlistAppAccessEnabled
    KEY = "skip_idp_ip_allowlist_app_access_enabled".freeze
    ENABLE_INSTRUMENTATION_KEY = "ip_allow_list.enable_skip_idp_ip_allowlist_app_access"
    DISABLE_INSTRUMENTATION_KEY = "ip_allow_list.disable_skip_idp_ip_allowlist_app_access"

    UNSUPPORTED_ENTERPRISE_ERROR = "Enterprise does not support skipping IdP IP allow list for installed GitHub applications"
    ENTERPRISE_OWNER_REQUIRED_ERROR = "Skip IdP IP allowlist for installed GitHub applications can only be changed by enterprise owner."
    IDP_IP_CONFIGURATION_REQUIRED_ERROR = "Unable to change Skip IdP check for applications since Identitiy Provider based IP allow list is not configured on enterprise."

    # Raised when skip IdP IP allowlist has issues when configuring.
    class SkipIdpIpAllowlistAppAccessError < StandardError; end

    # Public: Enable skip IdP based IP allow list app access on the object.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    def enable_skip_idp_ip_allowlist_app_access(actor: nil)
      unless eligible_for_skip_idp_ip_allowlist_app_access?
        raise SkipIdpIpAllowlistAppAccessError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      unless self.owner?(actor)
        raise SkipIdpIpAllowlistAppAccessError.new ENTERPRISE_OWNER_REQUIRED_ERROR
      end

      if !self.idp_based_ip_allowlist_configuration?
        raise SkipIdpIpAllowlistAppAccessError.new IDP_IP_CONFIGURATION_REQUIRED_ERROR
      end

      return unless config.enable(KEY, actor)

      instrument_skip_idp_ip_allowlist_app_access(name: ENABLE_INSTRUMENTATION_KEY, actor: actor)
    end

    # Public: Disable skip IdP based IP allow list app access on the object.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    def disable_skip_idp_ip_allowlist_app_access(actor: nil)
      unless eligible_for_skip_idp_ip_allowlist_app_access?
        raise SkipIdpIpAllowlistAppAccessError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      unless self.owner?(actor)
        raise SkipIdpIpAllowlistAppAccessError.new ENTERPRISE_OWNER_REQUIRED_ERROR
      end

      if !self.idp_based_ip_allowlist_configuration?
        raise SkipIdpIpAllowlistAppAccessError.new IDP_IP_CONFIGURATION_REQUIRED_ERROR
      end

      return unless config.delete(KEY, actor)

      instrument_skip_idp_ip_allowlist_app_access(name: DISABLE_INSTRUMENTATION_KEY, actor: actor)
    end

    # Public: Is Skip IdP IP allow list app access enabled on the object?
    #
    # Returns Boolean.
    def skip_idp_ip_allowlist_app_access_enabled?
      config.enabled?(KEY)
    end

    # Public: is self an EMU business with OIDC?
    #
    # Returns Boolean.
    def eligible_for_skip_idp_ip_allowlist_app_access?
      return false unless self.is_a?(Business)
      return false unless self.enterprise_managed_user_enabled?
      return false unless self.oidc_enabled?

      true
    end

    private

    # Private: Instrument skip IdP IP allow list app access event.
    #
    # Returns nothing.
    def instrument_skip_idp_ip_allowlist_app_access(name:, actor:)
      payload = {
        actor: actor,
        business: self
      }

      GitHub.instrument(name, payload)
    end
  end
end
