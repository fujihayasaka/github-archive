# typed: false
# frozen_string_literal: true

# This configurable is for EMU OIDC customers with IdP CAP already enabled for IP allow list.
# These are customers who, during the public beta of IdP CAP for web, will be able to opt in
# or opt out of the new web part of the feature. After GA all customers will be forced to use
# web and this configurable will be removed.
module Configurable
  module IdpIpAllowlistForWeb
    KEY = "idp_ip_allowlist_for_web".freeze
    ENABLE_INSTRUMENTATION_KEY = "ip_allow_list.enable_idp_ip_allowlist_for_web"
    DISABLE_INSTRUMENTATION_KEY = "ip_allow_list.disable_idp_ip_allowlist_for_web"

    UNSUPPORTED_ENTERPRISE_ERROR = "Enterprise does not support configuring Identity Provider based IP allow list for web."
    ENTERPRISE_OWNER_REQUIRED_ERROR = "Identity Provider based IP allow list for web can only be configured by enterprise owner."
    ENTERPRISE_TOO_MANY_USERS_ERROR = "Enterprise has too many users to enable Identity Provider based IP allow list for web."

    MAX_USERS_PER_BUSINESS = 1000

    # Raise when IdP IP allowlist for web has issues when configuring.
    class IdpIpAllowlistForWebError < StandardError; end

    # Public: Enable IdP IP allowlist for web on the object.
    #
    # actor - The User enabling the setting.
    def enable_idp_ip_allowlist_for_web(actor: nil)
      unless eligible_for_idp_ip_allowlist_for_web_configurable?
        raise IdpIpAllowlistForWebError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      unless user_count_allowed_for_idp_ip_allowlist_for_web_configurable?
        raise IdpIpAllowlistForWebError.new ENTERPRISE_TOO_MANY_USERS_ERROR
      end

      unless self.owner?(actor)
        raise IdpIpAllowlistForWebError.new ENTERPRISE_OWNER_REQUIRED_ERROR
      end

      return unless config.enable(KEY, actor)

      instrument_idp_ip_allowlist_for_web(name: ENABLE_INSTRUMENTATION_KEY, actor: actor)
    end

    # Public: Disable IdP IP allowlist for web on the object.
    #
    # actor - The User enabling the setting.
    def disable_idp_ip_allowlist_for_web(actor: nil)
      unless eligible_for_idp_ip_allowlist_for_web_configurable?
        raise IdpIpAllowlistForWebError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      unless self.owner?(actor)
        raise IdpIpAllowlistForWebError.new ENTERPRISE_OWNER_REQUIRED_ERROR
      end

      return unless config.delete(KEY, actor)

      instrument_idp_ip_allowlist_for_web(name: DISABLE_INSTRUMENTATION_KEY, actor: actor)
    end

    # Public: Is IdP IP allowlist for web enabled on the object?
    #
    # Returns Boolean.
    def idp_ip_allowlist_for_web_configurable_enabled?
      config.enabled?(KEY)
    end

    # Public: Is self an EMU business with OIDC with feature flag `idp_cap_web_configurable_allowed` enabled?
    #  `idp_cap_web_configurable_allowed` tracks businesses that already had IdP CAP enabled
    # for IP allowlist prior to the web feature being shipped.
    # `idp_cap_for_web` should also be enabled for this to work.
    def eligible_for_idp_ip_allowlist_for_web_configurable?
      return false unless self.is_a?(Business)
      return false unless self.enterprise_managed_user_enabled?
      return false unless self.oidc_enabled?
      return false unless self.feature_enabled?(:idp_cap_for_web)
      return false unless self.feature_enabled?(:idp_cap_web_configurable_allowed)
      return false unless self.idp_based_ip_allowlist_configuration?

      true
    end

    def user_count_allowed_for_idp_ip_allowlist_for_web_configurable?
      self.user_accounts.count <= MAX_USERS_PER_BUSINESS
    end

    private

    # Private: Instrument IdP IP allowlist for web configuration update event.
    def instrument_idp_ip_allowlist_for_web(name:, actor:)
      payload = {
        actor: actor,
        business: self,
      }

      GitHub.instrument(name, payload)
    end
  end
end
