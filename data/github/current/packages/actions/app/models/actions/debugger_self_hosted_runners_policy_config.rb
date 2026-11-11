# typed: strict
# frozen_string_literal: true

# Policy that controls whether self-hosted runners are allowed for jobs that
# use the Actions Job Debugger, at enterprise / organization / repository
# level. Strictest setting wins: if any ancestor disallows, descendants are
# disallowed regardless of their local value.
#
# This policy becomes active whenever the existing debugger feature flag is
# enabled for the entity or any ancestor. Once active, the policy defaults to
# `false` and an admin must explicitly turn it on at the relevant level.
class Actions::DebuggerSelfHostedRunnersPolicyConfig
  include Instrumentation::Model

  KEY = "actions_debugger_self_hosted_runners_allowed"

  sig { returns(T.any(Business, Organization, Repository)) }
  attr_reader :entity

  sig { params(entity: T.any(Business, Organization, Repository)).void }
  def initialize(entity)
    @entity = entity
  end

  # Is the policy active for this entity (gated behind the existing debugger
  # feature flag at this entity or any ancestor)?
  sig { returns(T::Boolean) }
  def feature_flag_enabled?
    debugger_ff_enabled?
  end

  # Effective `allowed?` taking the full ancestor hierarchy into account
  # (strictest wins).
  sig { returns(T::Boolean) }
  def allowed?
    return true unless feature_flag_enabled?

    owner = owner_policy_config
    return false if owner && !owner.allowed?

    local_allowed?
  end

  sig { returns(T::Boolean) }
  def disallowed_by_owner?
    return false unless feature_flag_enabled?

    owner = owner_policy_config
    return false unless owner

    owner.locally_disallowed? || owner.disallowed_by_owner?
  end

  # The value set directly on this entity, ignoring inheritance. Defaults to
  # `false` when nothing is set locally.
  sig { returns(T::Boolean) }
  def local_allowed?
    return false unless entity.config.local?(KEY)

    !!entity.config.enabled?(KEY)
  end

  # True when this entity has an explicit local `false` value (as opposed to
  # being unset, which is also treated as "not allowed" but is not the same
  # as an admin opting children out).
  sig { returns(T::Boolean) }
  def locally_disallowed?
    return false unless entity.config.local?(KEY)

    !entity.config.enabled?(KEY)
  end

  # Children may still set their own value (strict-wins is enforced at read
  # time via `allowed?`).
  sig { params(actor: User).returns(T::Boolean) }
  def allow(actor:)
    old_value = allowed?
    updated = entity.config.enable(KEY, actor)
    instrument_policy_update(old_value, actor) if updated
    updated
  end

  sig { params(actor: User).returns(T::Boolean) }
  def disallow(actor:)
    old_value = allowed?
    updated = entity.config.disable(KEY, actor)
    instrument_policy_update(old_value, actor) if updated
    updated
  end

  # used for testing
  sig { params(actor: User).returns(T::Boolean) }
  def clear(actor:)
    entity.config.delete(KEY, actor)
  end

  private

  # Is the parent debugger feature flag on for this entity or any ancestor?
  # Mirrors {#feature_flag_enabled?} cascade so EMU repos pick up the FF from
  # the enterprise-managed business.
  sig { returns(T::Boolean) }
  def debugger_ff_enabled?
    return true if FeatureFlag.vexi.enabled?(:actions_enable_debugger, entity, default: false)

    owner = owner_policy_config
    return false unless owner

    owner.send(:debugger_ff_enabled?)
  end

  sig { returns(T.nilable(Actions::DebuggerSelfHostedRunnersPolicyConfig)) }
  def owner_policy_config
    e = entity
    if e.is_a?(Business)
      nil
    elsif e.is_a?(Organization)
      business = e.business
      return nil if business.nil?
      Actions::DebuggerSelfHostedRunnersPolicyConfig.new(business)
    elsif e.is_a?(Repository)
      owner = e.owner
      return nil if owner.nil?
      if owner.is_a?(Organization)
        return Actions::DebuggerSelfHostedRunnersPolicyConfig.new(owner)
      end
      # EMU user-owned repos cascade up to the enterprise managed business.
      if e.is_enterprise_managed?
        business = owner.enterprise_managed_business
        return nil if business.nil?
        return Actions::DebuggerSelfHostedRunnersPolicyConfig.new(business)
      end
      nil
    else
      T.absurd(e)
    end
  end

  sig { params(old_value: T::Boolean, actor: User).void }
  def instrument_policy_update(old_value, actor)
    entity.instrument :update_actions_debugger_self_hosted_runners_policy,
      old_actions_debugger_self_hosted_runners_allowed: old_value,
      new_actions_debugger_self_hosted_runners_allowed: allowed?,
      actor: actor
  end
end
