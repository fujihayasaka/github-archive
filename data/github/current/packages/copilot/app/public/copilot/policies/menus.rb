# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Menus
      DEFAULT = T.let([
          Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy,
          Copilot::Policies::MenuItems::GeneralPolicies::Enabled,
          Copilot::Policies::MenuItems::GeneralPolicies::Disabled,
        ], T::Array[T.any(T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy), T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Enabled), T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Disabled))])

      ALLOW_OR_BLOCK = T.let([
          Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy,
          Copilot::Policies::MenuItems::GeneralPolicies::Allowed,
          Copilot::Policies::MenuItems::GeneralPolicies::Blocked,
        ], T::Array[T.any(T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy), T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Allowed), T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Blocked))])

      EA_USER_FALLBACK = T.let([
          Copilot::Policies::MenuItems::EaUserFallback::Enabled,
          Copilot::Policies::MenuItems::EaUserFallback::Disabled,
        ], T::Array[T.any(T.class_of(Copilot::Policies::MenuItems::EaUserFallback::Enabled), T.class_of(Copilot::Policies::MenuItems::EaUserFallback::Disabled))])

      MCP_ALLOWLIST = T.let([
        Copilot::Policies::MenuItems::McpRegistryAccess::AllowAll,
          Copilot::Policies::MenuItems::McpRegistryAccess::RegistryOnly
      ], T::Array[T.any(T.class_of(Copilot::Policies::MenuItems::McpRegistryAccess::AllowAll), T.class_of(Copilot::Policies::MenuItems::McpRegistryAccess::RegistryOnly))])
    end
  end
end
