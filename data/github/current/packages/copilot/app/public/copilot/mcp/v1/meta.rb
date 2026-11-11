# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module V1
      # Builder for the v1 response's `_meta` envelope.
      #
      # Per RFC github/copilot-ecosystem#934 §2, the v1 response carries a
      # top-level `_meta` object keyed by reverse-DNS namespaces so future
      # GitHub-controlled additions (and unrelated additions by other Copilot
      # surfaces) cannot collide. The initial release ships two keys:
      #
      #   * `com.github.copilot/spec_version`   \u2014 the spec version actually
      #     served, after resolving `X-Spec-Version`. Always echoed so
      #     clients can confirm what shape they parsed.
      #   * `com.github.copilot/enforcement`    \u2014 a hint object describing how
      #     the user's MCP allowlist is enforced. `mode` is `"allowlist"` for
      #     the initial release; `allowlist_available` indicates whether the
      #     GitHub-native allowlist UI is currently exposed to this user
      #     (i.e. the feature flag is enabled on any of the user's Copilot
      #     enterprises, or directly on the user \u2014 the two signals are
      #     ORed so an actor-level override also lights up the UI for CFE
      #     users).
      #
      # Helping clients distinguish "no allowlist available yet" from
      # "allowlist available but empty" is the point of `allowlist_available`.
      # An empty `mcp_registries` array combined with `allowlist_available:
      # true` means "the allowlist is in effect and currently allows nothing";
      # `allowlist_available: false` means "the allowlist surface is not
      # available for this user".
      module Meta
        include Copilot::Mcp::EnterpriseRegistryShared

        SPEC_VERSION_KEY = T.let("com.github.copilot/spec_version", String)
        ENFORCEMENT_KEY = T.let("com.github.copilot/enforcement", String)
        ALLOWLIST_MODE = T.let("allowlist", String)

        sig { params(copilot_user: ::Copilot::User, spec_version: String).returns(T::Hash[String, T.anything]) }
        def self.build(copilot_user, spec_version)
          {
            SPEC_VERSION_KEY => spec_version,
            ENFORCEMENT_KEY => {
              mode: ALLOWLIST_MODE,
              allowlist_available: allowlist_available?(copilot_user),
            },
          }
        end

        # `allowlist_available?` is true when any business the user belongs to
        # has the GitHub-native MCP allowlist UI feature flag enabled, or when
        # the flag is enabled on the user directly. The check delegates to the
        # shared helper so this signal stays in lock-step with the Settings UI.
        sig { params(copilot_user: ::Copilot::User).returns(T::Boolean) }
        def self.allowlist_available?(copilot_user)
          user = copilot_user.user_object
          shim = EnterpriseRegistrySharedShim.new
          businesses = copilot_user.copilot_businesses_all
          return shim.mcp_registry_allowlist_ui_enabled?(user, nil) if businesses.empty?

          businesses.any? do |biz|
            shim.mcp_registry_allowlist_ui_enabled?(user, biz)
          end
        end

        # Tiny shim so the module-level `Meta.build` (and its callers, which
        # are also modules) can reach `EnterpriseRegistryShared`'s instance
        # methods without forcing every call site to mix the module in.
        class EnterpriseRegistrySharedShim
          include Copilot::Mcp::EnterpriseRegistryShared
        end
      end
    end
  end
end
