# typed: true
# frozen_string_literal: true

# Manage whether Integrations are allowed to access content that is protected
# with an IP allow list. If disabled, all Integration access will be denied,
# otherwise the org or business allow list, as well as the allow list for the
# Integration is checked to determine if the request is from a trusted source.
# Currently included by Organization and Business.
module Configurable
  module IpAllowlistAppAccessEnabled
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "ip_allowlist_app_access_enabled".freeze

    # Raised when enabling for an object that does not have GitHub based IP allow list configuration enabled
    class GitHubConfigurationRequiredError < StandardError; end

    # Public: Enable IP allow list app access on the object.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    def enable_ip_allowlist_app_access(actor: nil)
      if github_configuration_required?
        raise GitHubConfigurationRequiredError.new \
          "Unable to enable IP allow list configuration for GitHub apps since GitHub based IP allow list is not enabled on enterprise."
      end

      return unless config.enable!(KEY, actor)

      instrument_enable_app_access(actor)
    end

    # Public: Disable IP allow list app access on the object.
    #
    # actor - The User disabling the setting.
    # reason - An optional String representing the reason for disabling.
    #
    # Returns nothing.
    def disable_ip_allowlist_app_access(actor: nil, reason: nil)
      return unless config.delete(KEY, actor)

      instrument_disable_app_access(actor, reason)
    end

    # Public: Is IP allow list app access enabled on the object?
    #
    # Returns Boolean.
    def ip_allowlist_app_access_enabled?
      GitHub.ip_allowlists_available? && config.enabled?(KEY)
    end

    # Public: Is IP allow list app access enabled at on a higher level object?
    #
    # For example, currently returns true when called on an org that is a member
    # of a business that has IP allow list enabled.
    #
    # Returns Boolean.
    def ip_allowlist_app_access_enabled_policy?
      ip_allowlist_app_access_enabled? && config.inherited?(KEY)
    end

    private

    def instrument_enable_app_access(actor)
      GitHub.instrument("ip_allow_list.enable_for_installed_apps", instrumentation_app_access_payload(actor))

      GlobalInstrumenter.instrument("ip_allow_list.enable_for_installed_apps", {
        owner: self,
        actor: actor,
      })
    end

    def instrument_disable_app_access(actor, reason)
      payload = instrumentation_app_access_payload(actor)
      payload[:reason] = reason unless reason.blank?
      GitHub.instrument("ip_allow_list.disable_for_installed_apps", payload)

      GlobalInstrumenter.instrument("ip_allow_list.disable_for_installed_apps", {
        owner: self,
        actor: actor,
      })
    end

    def instrumentation_app_access_payload(actor)
      payload = { user: actor }

      case self
      when ::Organization
        payload[:org] = self
        payload[:business] = self.business if self.business
      when ::Business
        payload[:business] = self
      end

      payload
    end

    def github_configuration_required?
      business = if self.is_a?(Business)
        self
      elsif self.is_a?(Organization)
        self.business
      else
        nil
      end

      return false unless business&.eligible_for_ip_allowlist_configuration?

      case self
      when ::Organization
        # prevent enabling on orgs when business has IdP based configuration enabled
        return true if business.idp_based_ip_allowlist_configuration?
        # allow otherwise
        false
      when ::Business
        # prevent enabling on business when business does not have GitHub based configuration enabled
        return true unless business.github_based_ip_allowlist_configuration?
        # allow otherwise
        false
      else
        false
      end
    end
  end
end
