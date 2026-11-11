# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    # Centralised feature-flag gates for MCP registry behavior. Encapsulates the
    # flag-name strings and the enterprise-OR-actor evaluation in one place so
    # callers do not drift on default values or mistype flag names. Each helper
    # returns the flag's effective state for a given Copilot user, honoring the
    # flag at both the enterprise (any of the user's Copilot enterprises) and
    # actor (the user themself) scopes.
    module FeatureFlags
      # Feature flag controlling whether the legacy /copilot/mcp_registry
      # endpoint filters out registries whose source is the GitHub-native
      # GitHub Enterprise MCP Registry. Default off so URL-only legacy clients
      # (e.g., the CLI allowlist integration) keep receiving the GitHub
      # Enterprise URL until they have migrated to the versioned /v1 endpoint.
      LEGACY_EXCLUDE_GITHUB_ENTERPRISE_REGISTRY = T.let(
        :copilot_mcp_registry_legacy_exclude_github_enterprise,
        Symbol,
      )

      # Returns true when the legacy /copilot/mcp_registry endpoint should drop
      # GitHub Enterprise MCP Registry entries for this Copilot user. The flag
      # is considered enabled when it is turned on for *either* the user
      # (actor) or any of the user's Copilot enterprises, defaulting to false.
      sig { params(copilot_user: ::Copilot::User).returns(T::Boolean) }
      def self.legacy_exclude_github_enterprise_registry?(copilot_user)
        copilot_user.copilot_businesses.any? do |copilot_business|
          copilot_business.feature_flag_enabled?(
            LEGACY_EXCLUDE_GITHUB_ENTERPRISE_REGISTRY,
            default: false,
          )
        end ||
          copilot_user.feature_flag_enabled?(
            LEGACY_EXCLUDE_GITHUB_ENTERPRISE_REGISTRY,
            default: false,
          ) ||
          false
      end
    end
  end
end
