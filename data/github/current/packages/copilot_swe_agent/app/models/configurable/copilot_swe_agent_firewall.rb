# typed: strict
# frozen_string_literal: true

# Manage Copilot coding agent firewall configuration for an organization.
# Encapsulates the three firewall Configurable keys: enabled, use_default_rules, and allow_custom_rules.
#
# Each setting supports three states:
# - nil (no policy) — defer to the repository-level setting
# - true — explicitly enabled
# - false — explicitly disabled
#
# Currently included by Organization.
module Configurable
  module CopilotSweAgentFirewall
    extend T::Helpers

    requires_ancestor { Configurable }

    FIREWALL_ENABLED_KEY = "copilot_agent_firewall_enabled"
    FIREWALL_USE_DEFAULT_RULES_KEY = "copilot_agent_firewall_use_default_rules"
    FIREWALL_ALLOW_CUSTOM_RULES_KEY = "copilot_agent_firewall_allow_custom_rules"

    # Boolean readers — collapse nil (unset) to a safe default.
    # Use these when you need a definitive true/false answer.

    sig { returns(T::Boolean) }
    def copilot_swe_agent_firewall_enabled?
      config.raw(FIREWALL_ENABLED_KEY) != "false"
    end

    sig { returns(T::Boolean) }
    def copilot_swe_agent_firewall_use_default_rules?
      config.raw(FIREWALL_USE_DEFAULT_RULES_KEY) != "false"
    end

    sig { returns(T::Boolean) }
    def copilot_swe_agent_firewall_allow_custom_rules?
      config.raw(FIREWALL_ALLOW_CUSTOM_RULES_KEY) == "true"
    end

    # Nullable policy readers — return nil when no policy has been set.
    # Use these when you need to distinguish "no policy" from an explicit value.

    sig { returns(T.nilable(T::Boolean)) }
    def copilot_swe_agent_firewall_enabled_policy
      raw = config.raw(FIREWALL_ENABLED_KEY)
      return nil if raw.nil?

      raw != "false"
    end

    sig { returns(T.nilable(T::Boolean)) }
    def copilot_swe_agent_firewall_use_default_rules_policy
      raw = config.raw(FIREWALL_USE_DEFAULT_RULES_KEY)
      return nil if raw.nil?

      raw != "false"
    end

    sig { returns(T.nilable(T::Boolean)) }
    def copilot_swe_agent_firewall_allow_custom_rules_policy
      raw = config.raw(FIREWALL_ALLOW_CUSTOM_RULES_KEY)
      return nil if raw.nil?

      raw == "true"
    end

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def copilot_swe_agent_firewall_config
      {
        enabled: copilot_swe_agent_firewall_enabled?,
        useDefaultRules: copilot_swe_agent_firewall_use_default_rules?,
        allowCustomRules: copilot_swe_agent_firewall_allow_custom_rules?,
      }
    end

    sig { params(enabled: T.nilable(T::Boolean), use_default_rules: T.nilable(T::Boolean), allow_custom_rules: T.nilable(T::Boolean), actor: User).void }
    def update_copilot_swe_agent_firewall(enabled:, use_default_rules:, allow_custom_rules:, actor:)
      set_or_delete_firewall_config(FIREWALL_ENABLED_KEY, enabled, actor)
      set_or_delete_firewall_config(FIREWALL_USE_DEFAULT_RULES_KEY, use_default_rules, actor)
      set_or_delete_firewall_config(FIREWALL_ALLOW_CUSTOM_RULES_KEY, allow_custom_rules, actor)
    end

    private

    sig { params(key: String, value: T.nilable(T::Boolean), actor: User).void }
    def set_or_delete_firewall_config(key, value, actor)
      if value.nil?
        config.delete(key, actor)
      else
        config.set!(key, value.to_s, actor)
      end
    end
  end
end
