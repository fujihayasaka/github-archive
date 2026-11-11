# typed: strict
# frozen_string_literal: true

# Actions debugger policy configuration.
# This wraps an entity (Business, Organization, or Repository) and provides
# debugger access policy functionality without mixing into the entity class.
#
# The debugger is disabled by default at all levels (opt-in). Stricter settings
# always win top-down. Enterprises and orgs can choose to enable for all child
# entities, selected entities, or none.
class Actions::DebuggerPolicyConfig
  include Instrumentation::Model

  KEY = "actions_debugger_enabled"

  ENTITY_KEY = "actions_debugger_allowed_by_owner"

  ALL_ENTITIES = "all"
  SELECTED_ENTITIES = "selected"
  NO_ENTITIES = "none"

  DEFAULT_VALUE = NO_ENTITIES

  sig { returns(T.any(Business, Organization, Repository)) }
  attr_reader :entity

  sig { params(entity: T.any(Business, Organization, Repository)).void }
  def initialize(entity)
    @entity = entity
  end

  # Is the debugger enabled for this entity (considering FF + policy hierarchy)?
  sig { returns(T::Boolean) }
  def enabled?
    return false unless feature_flag_enabled?

    !disabled?
  end

  # The effective access policy for this entity (accounting for parent restrictions).
  sig { returns(String) }
  def access
    return NO_ENTITIES if disabled_by_owner?

    local_access
  end

  # The access policy set directly on this entity (ignoring inheritance).
  sig { returns(String) }
  def local_access
    if entity.config.local?(KEY)
      entity.config.raw(KEY) || default_value
    else
      default_value
    end
  end

  sig { returns(String) }
  def default_value
    # Enterprise defaults to enabled so orgs can opt in without enterprise action.
    # Orgs and repos default to disabled (explicit opt-in required).
    entity.is_a?(Business) ? ALL_ENTITIES : NO_ENTITIES
  end

  sig { returns(T::Boolean) }
  def enabled_for_all_entities?
    access == ALL_ENTITIES
  end

  sig { returns(T::Boolean) }
  def enabled_for_selected_entities?
    access == SELECTED_ENTITIES
  end

  sig { returns(T::Boolean) }
  def disabled?
    access == NO_ENTITIES
  end

  # Enable the debugger for all child entities.
  # Uses set! with final=false so children can set their own policy.
  sig { params(actor: User).returns(T::Boolean) }
  def enable(actor:)
    old_policy = access
    updated = config.set!(KEY, ALL_ENTITIES, actor, false)
    instrument_policy_update(old_policy, actor) if updated
    updated
  end

  # Enable the debugger for selected child entities only.
  sig { params(actor: User).returns(T::Boolean) }
  def enable_for_selected_entities(actor:)
    old_policy = access
    updated = config.set!(KEY, SELECTED_ENTITIES, actor, false)
    instrument_policy_update(old_policy, actor) if updated
    updated
  end

  # Disable the debugger. Uses set! with final=true to block children from overriding.
  sig { params(actor: User).returns(T::Boolean) }
  def disable(actor:)
    old_policy = access
    updated = config.set!(KEY, NO_ENTITIES, actor, true)
    instrument_policy_update(old_policy, actor) if updated
    updated
  end

  # Remove the setting entirely (for testing).
  sig { params(actor: User).returns(T::Boolean) }
  def clear(actor:)
    config.delete(KEY, actor)
  end

  # Set the entity-level allow policy (for selected-mode allowlisting).
  sig { params(allowed: T::Boolean, actor: User).void }
  def set_entity_policy(allowed:, actor:)
    if allowed
      config.enable(ENTITY_KEY, actor)
    else
      config.disable(ENTITY_KEY, actor)
    end
  end

  # Remove the entity-level allow policy (for testing).
  sig { params(actor: User).returns(T::Boolean) }
  def clear_entity_policy(actor:)
    config.delete(ENTITY_KEY, actor)
  end

  # Is this entity explicitly allowed by its parent?
  sig { returns(T::Boolean) }
  def allowed_by_owner?
    !!config.local?(ENTITY_KEY) && config.enabled?(ENTITY_KEY)
  end

  # Is this entity restricted by its parent's policy?
  sig { returns(T::Boolean) }
  def disabled_by_owner?
    owner_config = owner_policy_config
    return false if owner_config.nil?

    owner_config.disabled? ||
      !!(owner_config.enabled_for_selected_entities? && !allowed_by_owner?)
  end

  # Does this entity's full hierarchy allow the debugger?
  sig { returns(T::Boolean) }
  def policy_allows_debugger?
    owner_config = owner_policy_config

    return true if owner_config.nil?

    return false unless owner_config.policy_allows_debugger?
    return true if owner_config.enabled_for_all_entities?
    return false if owner_config.disabled?

    # Owner is in "selected" mode — check if this entity is selected
    allowed_by_owner?
  end

  # Get IDs of child entities that are explicitly allowed.
  sig { returns(T::Array[Integer]) }
  def allowed_entity_ids
    entries = T.let([], T::Array[Integer])
    target_ids, target_type = selected_entity_target_info

    if target_ids.present? && target_type.present?
      target_ids.each_slice(500) do |slice|
        entries.concat ::Configuration::Entry
          .targeting_type(target_type)
          .named(ENTITY_KEY)
          .with_true_value
          .for_target_id(slice)
          .pluck(:target_id)
      end
    end

    entries
  end

  # Is the feature flag enabled for this entity or any parent?
  sig { returns(T::Boolean) }
  def feature_flag_enabled?
    return true if FeatureFlag.vexi.enabled?(:actions_enable_debugger, entity, default: false)

    owner_config = owner_policy_config
    return false unless owner_config

    owner_config.feature_flag_enabled?
  end

  private

  sig { returns(Configuration) }
  def config
    entity.config
  end

  sig { returns(T.nilable(Actions::DebuggerPolicyConfig)) }
  def owner_policy_config
    e = entity
    if e.is_a?(Business)
      nil
    elsif e.is_a?(Organization)
      business = e.business
      return nil if business.nil?
      Actions::DebuggerPolicyConfig.new(business)
    elsif e.is_a?(Repository)
      owner = e.owner
      return nil if owner.nil?
      return nil unless owner.is_a?(Organization)
      Actions::DebuggerPolicyConfig.new(owner)
    else
      T.absurd(e)
    end
  end

  sig { returns([T::Array[Integer], String]) }
  def selected_entity_target_info
    e = entity
    if e.is_a?(Business)
      [e.organization_ids, "User"]
    elsif e.is_a?(Organization)
      [e.repository_ids, "Repository"]
    elsif e.is_a?(Repository)
      [[], ""]
    else
      T.absurd(e)
    end
  end

  sig { params(old_policy: String, actor: User).void }
  def instrument_policy_update(old_policy, actor)
    entity.instrument :update_actions_debugger_policy,
      old_actions_debugger_policy: old_policy,
      new_actions_debugger_policy: access,
      actor: actor
  end
end
