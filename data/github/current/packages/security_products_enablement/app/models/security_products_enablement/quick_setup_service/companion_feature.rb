# typed: strict
# frozen_string_literal: true

# Encodes how a companion feature behaves relative to its feature group's Quick Setup state.
# Unlike core features, companions do not determine the group state — they only follow it.
#
# Core features are the primary capabilities that define what a Quick Setup toggle means
# (e.g., secret_scanning, push_protection, and validity_checks ARE "Secret Protection").
# Their values must all agree to establish the group state; if any differ, the group is "custom".
# On GHES, unavailable core features that are disabled are excluded from voting.
#
# Companion features are secondary/advanced capabilities that enhance core functionality
# (e.g., delegated_bypass enhances secret_scanning). Any deviation from the default
# companion value for the group state causes the group to become "custom".
#
# The `requires_core_enabled` flag controls behavior when the group is deferred (not_set):
#   - false (default): available whenever the group isn't disabled (e.g., delegated_bypass)
#   - true: disabled unless core is explicitly enabled (e.g., generic_secrets)
#
# The `recommended_when` proc gates whether a companion is promoted to "enabled" or left
# as "not_set" when the group is enabled. When nil (default), the companion follows standard
# behavior (always "not_set" when group is enabled). When present and returns true, the
# companion is "enabled" when the group is enabled (behaves like a core feature). When present
# and returns false, the companion stays "not_set". This is useful for features like
# validity_checks that should be enabled on GHEC but deferred on Proxima/GHES where data
# ownership concerns make auto-enabling inappropriate.
#
# Default companion value produced for each group state:
#
#                          | group=enabled | group=not_set | group=disabled |
#  ------------------------|---------------|---------------|----------------|
#  requires_core_enabled=F | not_set       | not_set       | disabled       |
#  requires_core_enabled=T | not_set       | disabled      | disabled       |
#  recommended_when=F      | not_set       | not_set       | disabled       |
#  recommended_when=T      | enabled       | not_set       | disabled       |
#
# Drift detection is two-phase:
#   Phase 1: Core features VOTE to establish the group state.
#            All core features must agree (e.g., all "enabled") or the group is "custom".
#   Phase 2: Companion features VALIDATE against the established state.
#            Each companion's actual value must match its default (from value_for_state).
#            Any deviation causes the group to become "custom".
#
# A companion can never upgrade a state — only veto it.
#
# Example (Secret Protection group):
#   Core: secret_scanning=enabled, push_protection=enabled
#         → Phase 1 establishes "enabled"
#
#   | Feature               | requires_core_enabled | recommended_when | Actual  | Acceptable for "enabled"? |
#   |-----------------------|-----------------------|------------------|---------|---------------------------|
#   | validity_checks       | false                 | → true (GHEC)    | enabled | yes (matches default)     |
#   | delegated_bypass      | false                 | nil              | not_set | yes (matches default)     |
#   | generic_secrets       | true                  | nil              | enabled | NO (default is not_set)   |
#   → generic_secrets drifted: group state is "custom"
#
class SecurityProductsEnablement::QuickSetupService::CompanionFeature < T::Struct
  State = SecurityProductsEnablement::QuickSetupService::State

  const :name, Symbol
  const :requires_core_enabled, T::Boolean, default: false
  # Optional proc that determines whether this companion should be promoted to "enabled"
  # when the group is enabled. When nil, standard companion behavior applies (not_set).
  # Example: `-> { !GitHub.single_or_multi_tenant_enterprise? }` makes the feature
  # enabled on GHEC but not_set on Proxima/GHES.
  const :recommended_when, T.nilable(T.proc.returns(T::Boolean)), default: nil

  sig { params(state: State).returns(State) }
  def value_for_state(state)
    case state
    when State::Enabled
      recommended_when&.call ? State::Enabled : State::NotSet
    when State::Disabled
      State::Disabled
    when State::NotSet
      requires_core_enabled ? State::Disabled : State::NotSet
    when State::Custom
      raise ArgumentError, "Cannot determine companion feature value for custom state"
    else
      T.absurd(state)
    end
  end

  # Whether this companion's actual value should cause the group state to become "custom".
  # Any deviation from the expected default value (from value_for_state) is drift.
  #
  sig { params(actual_value: T.nilable(State), state: State).returns(T::Boolean) }
  def drifted_to_custom?(actual_value, state)
    actual_value != value_for_state(state)
  end
end
