# typed: false
# frozen_string_literal: true

module Configurable
  module IpAllowlistConfiguration
    KEY = "ip_allowlist_configuration".freeze
    UPDATE_INSTRUMENTATION_KEY = "ip_allow_list.update_ip_allowlist_configuration"

    GITHUB = "github".freeze  #GitHub based IP allow list configuration enabled
    IDP = "idp".freeze #IDP based IP allow list configuration enabled
    DISABLED = "disabled".freeze #IP allow list configuration disabled
    CONFIG_VALUES = [GITHUB, IDP, DISABLED].freeze

    ENTERPRISE_OWNER_REQUIRED_ERROR = "IP allow list configuration can only be set by enterprise owner."
    UNSUPPORTED_CONFIG_VALUE = "You provided an invalid config value. Please try again."
    UNSUPPORTED_ENTERPRISE_ERROR = "Enterprise does not support IP allow list configuration."
    IDP_IP_ALLOW_LIST_ENABLED_ERROR = "IP allow list must be disabled for the enterprise and all organizations to enable IdP managed IP allow list configuration."
    DISABLED_IP_ALLOW_LIST_ENABLED_ERROR = "IP allow list must be disabled for the enterprise to disable IP allow list configuration."

    class IpAllowlistConfigurationError < StandardError; end

    # Public: Set IP allow list configuration on the object.
    #
    # Returns nothing.
    def update_ip_allowlist_configuration(actor: nil, config_value: nil)
      unless eligible_for_ip_allowlist_configuration?
        raise IpAllowlistConfigurationError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      unless self.owner?(actor)
        raise IpAllowlistConfigurationError.new ENTERPRISE_OWNER_REQUIRED_ERROR
      end

      unless CONFIG_VALUES.include?(config_value)
        raise IpAllowlistConfigurationError.new UNSUPPORTED_CONFIG_VALUE
      end

      if config_value == IDP && self.ip_allowlist_enabled_for_business_or_orgs?
        raise IpAllowlistConfigurationError.new IDP_IP_ALLOW_LIST_ENABLED_ERROR
      end

      if config_value == DISABLED && self.ip_allowlist_enabled?
        raise IpAllowlistConfigurationError.new DISABLED_IP_ALLOW_LIST_ENABLED_ERROR
      end

      return unless config.set!(KEY, config_value, actor)

      instrument_ip_allowlist_configuration(config_value: config_value, actor: actor)
    end

    # Public: Is IP allow list configuration set to be based on IdP
    #
    # Returns Boolean.
    def idp_based_ip_allowlist_configuration?
      config.get(KEY) == IDP
    end

    # Public: Is IP allow list configuration set to be based on GitHub
    #
    # Returns Boolean.
    def github_based_ip_allowlist_configuration?
      config.get(KEY) == GITHUB
    end

    # Public: Is IP allow list configuration set to be disabled
    #
    # Returns Boolean.
    def disabled_ip_allowlist_configuration?
      config.get(KEY) == DISABLED || config.get(KEY).nil?
    end

    # Public: is self an EMU business with OIDC?
    #
    # Returns Boolean.
    def eligible_for_ip_allowlist_configuration?
      return false unless self.is_a?(Business)
      return false unless self.enterprise_managed_user_enabled?
      return false unless self.oidc_enabled?

      true
    end

    # Private: Instrument ip allowlist configuration update event.
    #
    # Returns nothing.
    def instrument_ip_allowlist_configuration(config_value:, actor:)
      payload = {
        actor: actor,
        configuration_value: config_value,
        business: self
      }

      GitHub.instrument(UPDATE_INSTRUMENTATION_KEY, payload)
    end
  end
end
