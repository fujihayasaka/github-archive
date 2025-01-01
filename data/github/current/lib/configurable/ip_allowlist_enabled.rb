# typed: true
# frozen_string_literal: true

# Manage whether IP allow list enabled is enabled on an object.
# Currently included by Organization and Business.
module Configurable
  module IpAllowlistEnabled
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "ip_allowlist_enabled".freeze

    # Raised when enabling the setting would lock the actor out of the
    # owning account.
    class ActorLockoutError < StandardError; end

    # Raised when using a method with an object other than a business.
    class NonBusinessError < StandardError; end

    # Raised when enabling for an object that does not have GitHub based IP allow list configuration enabled
    class GitHubConfigurationRequiredError < StandardError; end

    # Public: Enable IP allow list on the object.
    #
    # actor - The User enabling the setting.
    # actor_ip - A String representing the IP address of the user enabling the setting.
    #
    # Returns nothing.
    def enable_ip_allowlist(actor: nil, actor_ip: nil)
      if enabling_will_lock_out_actor?(actor_ip)
        raise ActorLockoutError.new \
          "Enabling an IP allow list would prevent you from accessing the account from your current IP address."
      end

      if github_configuration_required?
        raise GitHubConfigurationRequiredError.new \
          "Unable to enable IP allow list since GitHub based IP allow list is not enabled on enterprise."
      end

      return unless config.enable!(KEY, actor)

      instrument_enable(actor)
    end

    # Public: Disable IP allow list on the object.
    #
    # actor - The User disabling the setting.
    # reason - An optional String representing the reason for disabling.
    #
    # Returns nothing.
    def disable_ip_allowlist(actor: nil, reason: nil)
      return unless config.delete(KEY, actor)

      instrument_disable(actor, reason)
    end

    # Public: Disable IP allow list on business and associated organizations.
    #
    # actor - The User disabling the setting.
    # reason - An optional String representing the reason for disabling.
    #
    # Returns nothing.
    def disable_ip_allowlist_for_business_and_orgs(actor: nil, reason: nil)
      unless self.is_a?(Business)
        raise NonBusinessError.new \
          "Disabling IP allowlist for business and associated organization is only available for Business objects."
      end
      disable_ip_allowlist(actor: actor, reason: reason)

      self.organizations.each do |org|
        org.disable_ip_allowlist(actor: actor, reason: reason)
      end
    end

    # Public: Is IP allow list enabled on the object?
    #
    # Returns Boolean.
    def ip_allowlist_enabled?
      GitHub.ip_allowlists_available? && config.enabled?(KEY)
    end

    # Public: Is IP allow list enabled for the business or any associated organizations?
    #
    # Returns Boolean.
    def ip_allowlist_enabled_for_business_or_orgs?
      unless self.is_a?(Business)
        raise NonBusinessError.new \
          "Checking enabled status of IP allowlist for business and associated organization is only available for Business objects."
      end
      return false unless GitHub.ip_allowlists_available?
      return true if ip_allowlist_enabled?

      self.organizations.any?(&:ip_allowlist_enabled?)
    end

    # Public: Is IP allow list enabled at on a higher level object?
    #
    # For example, currently returns true when called on an org that is a member
    # of a business that has IP allow list enabled.
    #
    # Returns Boolean.
    def ip_allowlist_enabled_policy?
      ip_allowlist_enabled? && config.inherited?(KEY)
    end

    # Public: Is IP allow list enabled but not on a higher level object?
    #
    # For example, currently returns true when called on an org that has IP allow list enabled that is a member
    # of a business that does not have IP allow list enabled.
    #
    # Returns Boolean.
    def ip_allowlist_enabled_local?
      ip_allowlist_enabled? && config.local?(KEY)
    end

    private

    def enabling_will_lock_out_actor?(actor_ip)
      return false unless GitHub.ip_allowlists_available?
      return false if actor_ip.blank?

      active_entries = IpAllowlistEntry.usable_for(self).active.to_a
      return false if IpAllowlistEntry.ip_included_in_entries? \
        ip: actor_ip, entries: active_entries

      true
    end

    def instrument_enable(actor)
      GitHub.instrument("ip_allow_list.enable", instrumentation_payload(actor))

      GlobalInstrumenter.instrument("ip_allow_list.enable", {
        owner: self,
        entries: T.unsafe(self).ip_allowlist_entries,
        actor: actor,
      })
    end

    def instrument_disable(actor, reason)
      payload = instrumentation_payload(actor)
      payload[:reason] = reason unless reason.blank?
      GitHub.instrument("ip_allow_list.disable", payload)

      GlobalInstrumenter.instrument("ip_allow_list.disable", {
        owner: self,
        entries: T.unsafe(self).ip_allowlist_entries,
        actor: actor,
      })
    end

    def instrumentation_payload(actor)
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
