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
    end
  end
end
