# typed: true
# frozen_string_literal: true

# Manage whether IP allow list user-level enforcement is enabled on an object.
#
# This does not support defining IP allow lists at the user level. Rather, this
# allows an enterprise to enable IP allow list enforcement at the user level
# for users within the enterprise.
module Configurable
  module IpAllowlistUserLevelEnforcementEnabled
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }
    requires_ancestor { GitHub::FlipperActor }
    requires_ancestor { GitHub::VexiActor }

    KEY = "ip_allowlist_user_level_enforcement_enabled".freeze

    # Public: Is the object eligibile for IP allow list user-level enforcement?
    #
    # The only currently eligible object is a GHEC Business with EMU enabled.
    #
    # Return Boolean.
    def eligible_for_ip_allowlist_user_level_enforcement?
      GitHub.ip_allowlists_available? &&
      self.is_a?(::Business) &&
      FeatureFlag.vexi.enabled?(:ip_allowlist_user_level_enforcement, self, default: false) &&
      self.enterprise_managed_user_enabled?
    end

    # Public: Enable IP allow list user-level enforcement on the object.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    def enable_ip_allowlist_user_level_enforcement(actor: nil)
      return unless eligible_for_ip_allowlist_user_level_enforcement?
      return unless config.enable!(KEY, actor)

      instrument_enable_ip_allowlist_user_level_enforcement(actor)
    end

    # Public: Disable IP allow list user-level enforcement on the object.
    #
    # actor - The User disabling the setting.
    # reason - An optional String representing the reason for disabling.
    #
    # Returns nothing.
    def disable_ip_allowlist_user_level_enforcement(actor: nil, reason: nil)
      return unless config.delete(KEY, actor)

      instrument_disable_ip_allowlist_user_level_enforcement(actor, reason)
    end

    # Public: Is IP allow list user-level enforcement enabled on the object?
    #
    # Returns Boolean.
    def ip_allowlist_user_level_enforcement_enabled?
      return false unless GitHub.ip_allowlists_available?
      self.feature_flag_enabled?(:ip_allowlist_user_level_enforcement, default: false, memoize: false) && config.enabled?(KEY)
    end

    private

    def instrument_enable_ip_allowlist_user_level_enforcement(actor)
      GitHub.instrument \
        "ip_allow_list.enable_user_level_enforcement",
        ip_allowlist_user_level_enforcement_instrumentation_payload(actor)

      GlobalInstrumenter.instrument("ip_allow_list.enable_user_level_enforcement", {
        owner: self,
        actor: actor,
      })
    end

    def instrument_disable_ip_allowlist_user_level_enforcement(actor, reason)
      payload = ip_allowlist_user_level_enforcement_instrumentation_payload(actor)
      payload[:reason] = reason unless reason.blank?
      GitHub.instrument "ip_allow_list.disable_user_level_enforcement", payload

      GlobalInstrumenter.instrument("ip_allow_list.disable_user_level_enforcement", {
        owner: self,
        actor: actor,
      })
    end

    def ip_allowlist_user_level_enforcement_instrumentation_payload(actor)
      payload = { user: actor }

      case self
      when ::Business
        payload[:business] = self
      end

      payload
    end
  end
end
