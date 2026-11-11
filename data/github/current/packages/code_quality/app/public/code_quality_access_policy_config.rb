# typed: strict
# frozen_string_literal: true

# Code Quality Access Policy configuration.
# This wraps an entity (Business, Organization, or Repository) and provides
# Code Quality access policy functionality without mixing into the entity class.
#
# These configuration entries specify whether organizations and repos are allowed
# to enable GitHub Code Quality.
#
# We model the configuration with two entries:
# - code_quality.access: determines which access to give to child entities (all/selected/none).
#     This can be set on businesses wrt child entities (organizations), or on organizations
#     wrt child entities (repos)
# - code_quality.entity_allowed: determines whether the specific entity is allowed access
#     This is set on organizations or repos, in which case it is only meaningful if the above
#     setting for the business or organization (respectively) indicates that it permits selected
#     entities.
class CodeQualityAccessPolicyConfig
  include Instrumentation::Model

  # This key represents the value entities inherit. It takes one of the following 3 values.
  KEY = "code_quality.access"

  ALL_ENTITIES = "all"
  SELECTED_ENTITIES = "selected"
  NO_ENTITIES = "none"

  # This key represents whether the entity has been enabled,
  # but only applies when the parent business has "selected" access.
  ENTITY_KEY = "code_quality.entity_allowed"

  ENTITY_ALLOWED = "true"
  ENTITY_NOT_ALLOWED = "false"

  sig { returns(T.any(Business, Organization, Repository)) }
  attr_reader :entity

  sig { params(entity: T.any(Business, Organization, Repository)).void }
  def initialize(entity)
    @entity = entity
  end

  # Allow all members of this entity (which must be a Business or Organization) to enable code quality
  sig { params(actor: User).void }
  def allow_members_to_enable_code_quality(actor:)
    changed = config.set(KEY, ALL_ENTITIES, actor)
    instrument_policy_update(ALL_ENTITIES, actor) if changed
  end

  # Allow only selected members of this entity (which must be a Business or Organization) to enable code quality
  sig { params(actor: User).void }
  def allow_selected_members_to_enable_code_quality(actor:)
    changed = config.set(KEY, SELECTED_ENTITIES, actor)
    instrument_policy_update(SELECTED_ENTITIES, actor) if changed
  end

  # Disallow all members of this entity (which must be a Business or Organization) from enabling code quality
  sig { params(actor: User).void }
  def disallow_members_to_enable_code_quality(actor:)
    changed = config.set(KEY, NO_ENTITIES, actor)
    instrument_policy_update(NO_ENTITIES, actor) if changed
  end

  # Is this entity configured to allow enablement of code quality for all members?
  # Note that if the entity is configured to allow selected members only, this will return false,
  # even if all members are in fact selected.
  sig { returns(T::Boolean) }
  def all_members_can_enable_code_quality?
    !config.local?(KEY) || config.get(KEY) == ALL_ENTITIES
  end

  # Is this entity configured to allow enablement of code quality for selected members only?
  # Note that if the entity is configured to allow all/no members, this will return false,
  # even if all members are in fact selected.
  sig { returns(T::Boolean) }
  def selected_members_can_enable_code_quality?
    !!config.local?(KEY) && config.get(KEY) == SELECTED_ENTITIES
  end

  # Is this entity configured to disallow enablement of code quality for all members?
  # Note that if the entity is configured to allow all/selected members, this will return false,
  # even if no members are in fact selected.
  sig { returns(T::Boolean) }
  def no_members_can_enable_code_quality?
    !!config.local?(KEY) && config.get(KEY) == NO_ENTITIES
  end

  # Set the entity policy for this organization/repository.
  # Note that the owning entity (business/organization) must be in "selected" mode
  # for this to have any effect.
  sig { params(allowed: T::Boolean, actor: User).void }
  def set_code_quality_entity_policy(allowed:, actor:)
    policy = allowed ? ENTITY_ALLOWED : ENTITY_NOT_ALLOWED
    changed = config.set(ENTITY_KEY, policy, actor)
    instrument_entity_policy_update(policy, actor) if changed
  end

  # Is this entity allowed to toggle code quality?
  sig { returns(T::Boolean) }
  def policy_allows_code_quality_enablement?
    owner_config = owner_access_policy_config

    # If there's no owner, the entity is top-level and is therefore allowed to change the policy
    return true if owner_config.nil?

    # The owner itself needs to have access
    return false if !owner_config.policy_allows_code_quality_enablement?
    # If the owner has a blanket policy, respect that
    return true if owner_config.all_members_can_enable_code_quality?
    return false if owner_config.no_members_can_enable_code_quality?

    # The owner exists, and is neither in "all" nor "none" mode, so it's in "selected" mode,
    # so check if the entity is selected
    return false if !config.local?(ENTITY_KEY)
    config.get(ENTITY_KEY) == ENTITY_ALLOWED
  end

  # Get the IDs of selected entities allowed to enable code quality
  # Note that this only makes sense for Business and Organization, and
  # only identifies orgs/repos that are specifically allowed
  # (i.e. applicable when the parent is in "selected" mode). Even If the
  # parent has a blanket allow/disallow, this method will still return
  # the entities that _would_ be allowed if the parent were in "selected" mode.
  sig { returns(T::Array[Integer]) }
  def code_quality_selected_access_allowed_entities
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

  # Returns the IDs and type name of child entities that can be individually
  # selected when the policy is in "selected" mode.
  # For Business: returns organization IDs
  # For Organization: returns repository IDs
  # For Repository: returns empty (no children)
  sig { returns([T::Array[Integer], String]) }
  def selected_entity_target_info
    e = entity
    if e.is_a?(Business)
      # Rails polymorphic associations store "User" as target_type for Organization
      # records due to STI (Organization < User)
      [e.organization_ids, "User"]
    elsif e.is_a?(Organization)
      [e.repository_ids, "Repository"]
    elsif e.is_a?(Repository)
      # Repositories don't have child entities
      [[], ""]
    else
      T.absurd(e)
    end
  end



  private

  sig { returns(Configuration) }
  def config
    entity.config
  end

  sig { returns(T.nilable(T.any(Business, Organization, User))) }
  def configuration_owner
    entity.configuration_owner
  end

  # Returns the owner's access policy config for checking inherited permissions
  sig { returns(T.nilable(CodeQualityAccessPolicyConfig)) }
  def owner_access_policy_config
    e = entity
    if e.is_a?(Business)
      # Businesses have no owner
      nil
    elsif e.is_a?(Organization)
      business = e.business
      return nil if business.nil?
      CodeQualityAccessPolicyConfig.new(business)
    elsif e.is_a?(Repository)
      owner = e.owner
      return nil if owner.nil?
      return nil unless owner.is_a?(Organization)
      CodeQualityAccessPolicyConfig.new(owner)
    else
      T.absurd(e)
    end
  end

  sig { params(policy: String, actor: User).void }
  def instrument_policy_update(policy, actor)
    entity.instrument :code_quality_access_policy_update, new_policy: policy, actor: actor
  end

  sig { params(policy: String, actor: User).void }
  def instrument_entity_policy_update(policy, actor)
    entity.instrument :code_quality_entity_policy_update, new_policy: policy, actor: actor
  end
end
