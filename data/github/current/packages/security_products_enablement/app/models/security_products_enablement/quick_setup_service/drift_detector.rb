# typed: strict
# frozen_string_literal: true

class SecurityProductsEnablement::QuickSetupService::DriftDetector
  QuickSetupService = SecurityProductsEnablement::QuickSetupService
  State = QuickSetupService::State
  FeatureGroup = QuickSetupService::FeatureGroup

  class EffectiveCodeSecuritySkuState < T::Enum
    enums do
      Enabled = new
      Disabled = new
      BundledAdvancedSetupAmbiguous = new
    end
  end

  class FeatureStates < T::Struct
    const :secret_protection, State
    const :code_security, State
    const :dependabot, State

    sig { returns(T::Hash[Symbol, State]) }
    def to_hash
      {
        secret_protection:,
        code_security:,
        dependabot:,
      }
    end
  end

  class DriftContext < T::Struct
    const :states, FeatureStates
    const :effective_code_security_sku_state, EffectiveCodeSecuritySkuState
  end

  sig { params(organization: Organization, configuration: SecurityConfiguration).void }
  def initialize(organization:, configuration:)
    @organization = organization
    @configuration = configuration
    @services = T.let(
      SecurityProductsEnablement::SecurityProductsManager.new.services,
      T::Hash[Symbol, T::Boolean]
    )
  end

  # Compares the stored SecurityConfiguration against what Quick Setup would have produced
  # and reports, per feature group, whether it still matches a clean Quick Setup state
  # (enabled/disabled/not_set) or has drifted into a "custom" state.
  #
  # The work happens in three passes:
  #   1. Derive a state for each group from its own feature toggles (determine_feature_group_state).
  #   2. Reconcile the Code Security group against the SKU/GHAS billing flags, which are a second
  #      source of truth that can independently drift (reconcile_sku_drift).
  #   3. Reconcile Dependabot's Code-Security-dependent companion (DDAD), whose expected value
  #      depends on the effective Code Security SKU state (reconcile_dependabot_drift).
  sig { returns(FeatureStates) }
  def detect
    # Pass 1: each group votes on its own state purely from its feature toggles.
    states = FeatureStates.new(
      secret_protection: determine_feature_group_state(QuickSetupService::SECRET_PROTECTION_GROUP),
      code_security: determine_feature_group_state(QuickSetupService::CODE_SECURITY_GROUP),
      dependabot: determine_feature_group_state(QuickSetupService::DEPENDABOT_GROUP),
    )
    # Carry the per-group states plus a derived "is Code Security effectively on?" summary
    # through the remaining passes, since later passes depend on that summary.
    context = DriftContext.new(
      states:,
      effective_code_security_sku_state: effective_code_security_sku_state(states),
    )
    # Pass 2: fold in drift coming from the billing/SKU flags (may flip groups to Custom).
    context = reconcile_sku_drift(context)
    # Pass 3: fold in drift from Dependabot's Code-Security-dependent companion, then return states.
    reconcile_dependabot_drift(context).states
  end

  # Derives a single Quick Setup state for one feature group from its individual toggles.
  #
  # Two phases (see CompanionFeature docs): core features VOTE to establish the state, then
  # companion features VALIDATE against it. A companion can only veto (force Custom), never upgrade.
  sig { params(group: FeatureGroup).returns(State) }
  def determine_feature_group_state(group)
    # Phase 1 — collect the votes from the core features.
    # A core feature that is unavailable on this instance (e.g. not installed on GHES) AND
    # disabled is excluded from voting: its "disabled" is forced, not a real user choice.
    main_states = group.core_features.filter_map do |feature|
      actual = State.from_enum(@configuration[feature])
      next if @services[feature] != true && actual == State::Disabled
      actual
    end

    # Establish the group state from the votes:
    #   - no votes left -> fall back to SKU/derived state. This happens only when EVERY core
    #     feature was skipped above, i.e. each one is both unavailable on this instance and
    #     disabled (typical on GHES when the products in this group aren't installed). An
    #     available core feature always votes, so it can never leave main_states empty.
    #   - all votes agree -> that shared value is the state
    #   - votes disagree -> uniform_state stays nil, meaning Custom below
    uniform_state = if main_states.empty?
      state_when_no_core_features_available(group)
    elsif main_states.uniq.one?
      main_states.first
    end

    # Disagreeing (or indeterminate) core features immediately mean the group is Custom.
    return State::Custom unless uniform_state

    # Phase 2 — every companion must match the default value expected for uniform_state.
    # Same availability rule: an unavailable + disabled companion can't be a deliberate change.
    any_drift = group.companion_features.any? do |companion|
      actual = State.from_enum(@configuration[companion.name])
      next false if @services[companion.name] != true && actual == State::Disabled

      companion.drifted_to_custom?(actual, uniform_state)
    end

    # Any companion deviating from its expected default vetoes the clean state.
    any_drift ? State::Custom : uniform_state
  end

  private

  # Summarizes whether the Code Security SKU is effectively "on", which downstream reconciliation
  # relies on. The rule differs by billing model:
  #   - bundled (GHAS): the single GHAS entitlement covers BOTH Secret Protection and Code
  #     Security, so it is on if either group is anything other than disabled.
  #   - unbundled (metered): Code Security is unavailable when disabled or not set. A custom state
  #     remains effectively enabled so independent Code Security drift does not cascade to Dependabot.
  sig { params(states: FeatureStates).returns(EffectiveCodeSecuritySkuState) }
  def effective_code_security_sku_state(states)
    enabled = if bundled?
      states.secret_protection != State::Disabled || states.code_security != State::Disabled
    else
      states.code_security != State::Disabled && states.code_security != State::NotSet
    end

    enabled ? EffectiveCodeSecuritySkuState::Enabled : EffectiveCodeSecuritySkuState::Disabled
  end

  # Cross-checks the feature-derived states against the billing flags, which are a separate
  # source of truth. If they disagree, the affected group(s) are marked Custom.
  sig { params(context: DriftContext).returns(DriftContext) }
  def reconcile_sku_drift(context)
    secret_protection = context.states.secret_protection
    code_security = context.states.code_security
    sku_state = context.effective_code_security_sku_state

    if bundled?
      # Bundled: a single `enable_ghas` flag must agree with the effective Code Security state.
      ghas_should_be_enabled = sku_state == EffectiveCodeSecuritySkuState::Enabled
      if @configuration.enable_ghas != ghas_should_be_enabled
        if @configuration.enable_ghas && !ghas_should_be_enabled && advanced_setup_only?
          # GHES Special case: Bundled GHAS is enabled but the features say off, and only Code Scanning
          # Advanced Setup is available. Advanced Setup can't tell "disabled" apart from "not_set",
          # so we attribute the drift solely to Code Security and leave Secret Protection intact, and
          # record the ambiguity so the Dependabot pass can treat DDAD leniently.
          code_security = State::Custom
          sku_state = EffectiveCodeSecuritySkuState::BundledAdvancedSetupAmbiguous
        else
          # Otherwise the mismatch could stem from either bundled group, so flag both.
          secret_protection = State::Custom
          code_security = State::Custom
        end
      end
    else
      # Unbundled: each group has its own SKU flag; compare each independently.
      # to_security_config_tri_state maps enabled/disabled/other -> true/false/nil to match the column.
      if @configuration.secret_protection_sku_enabled != secret_protection.to_security_config_tri_state
        secret_protection = State::Custom
      end
      if @configuration.code_security_sku_enabled != code_security.to_security_config_tri_state
        code_security = State::Custom
      end
    end

    DriftContext.new(
      states: FeatureStates.new(
        secret_protection:,
        code_security:,
        dependabot: context.states.dependabot,
      ),
      effective_code_security_sku_state: sku_state,
    )
  end

  # Validates Dependabot companions that additionally depend on the Code Security SKU (the DDAD
  # feature — dependabot_delegated_alert_dismissal). These follow the Dependabot state normally but
  # must be forced off whenever Code Security is not effectively enabled, so their acceptable value
  # depends on the effective Code Security SKU state computed earlier.
  sig { params(context: DriftContext).returns(DriftContext) }
  def reconcile_dependabot_drift(context)
    # If Dependabot is already Custom there is nothing more to downgrade.
    return context if context.states.dependabot == State::Custom

    ddad_drift = QuickSetupService::DEPENDABOT_CODE_SECURITY_COMPANIONS.any? do |companion|
      actual = State.from_enum(@configuration[companion.name])
      # Same availability rule as elsewhere: unavailable + disabled isn't a deliberate change.
      next false if @services[companion.name] != true && actual == State::Disabled

      # What DDAD would be if it simply followed the Dependabot state.
      expected_when_available = companion.value_for_state(context.states.dependabot)
      sku_state = context.effective_code_security_sku_state
      # Which actual values are acceptable depends on Code Security's effective state:
      valid_states = case sku_state
      when EffectiveCodeSecuritySkuState::Enabled
        # Code Security on: DDAD must exactly follow Dependabot.
        [expected_when_available]
      when EffectiveCodeSecuritySkuState::Disabled
        # Code Security off: DDAD is forced disabled regardless of Dependabot.
        [State::Disabled]
      when EffectiveCodeSecuritySkuState::BundledAdvancedSetupAmbiguous
        # Ambiguous Advanced Setup case: we can't tell which of the two is correct, so accept either
        # to avoid falsely attributing Code Security's ambiguity to Dependabot.
        [State::Disabled, expected_when_available]
      else
        T.absurd(sku_state)
      end

      !valid_states.include?(actual)
    end

    # No DDAD deviation -> Dependabot state is unchanged.
    return context unless ddad_drift

    # DDAD drifted -> downgrade the Dependabot group to Custom.
    DriftContext.new(
      states: FeatureStates.new(
        secret_protection: context.states.secret_protection,
        code_security: context.states.code_security,
        dependabot: State::Custom,
      ),
      effective_code_security_sku_state: context.effective_code_security_sku_state,
    )
  end

  # Fallback used when a group has no votable core features (all unavailable on this instance).
  # Only Code Security can be inferred from other signals; every other group defaults to Disabled.
  sig { params(group: FeatureGroup).returns(T.nilable(State)) }
  def state_when_no_core_features_available(group)
    return State::Disabled unless group == QuickSetupService::CODE_SECURITY_GROUP

    if bundled?
      # Bundled without Code Scanning available: infer from the delegated-alert-dismissal companion,
      # the only Code Security signal we still have. (Returns nil for unexpected values -> Custom.)
      case State.from_enum(@configuration.code_scanning_delegated_alert_dismissal)
      when State::NotSet then State::Enabled
      when State::Disabled then State::Disabled
      end
    else
      # Unbundled: the Code Security SKU flag directly encodes enabled/disabled/not_set.
      case @configuration.code_security_sku_enabled
      when true then State::Enabled
      when false then State::Disabled
      when nil then State::NotSet
      end
    end
  end

  # True when Code Scanning Default Setup is unavailable but its delegated-alert-dismissal companion
  # is available — i.e. only Advanced Setup exists, which can't distinguish disabled from not_set.
  sig { returns(T::Boolean) }
  def advanced_setup_only?
    @services[:code_scanning] != true && @services[:code_scanning_delegated_alert_dismissal] == true
  end

  sig { returns(T::Boolean) }
  def bundled?
    @organization.advanced_security_products_bundled?
  end
end
