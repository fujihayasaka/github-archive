# typed: true
# frozen_string_literal: true

# These configuration entries specifies whether repository admins are allowed
# to enable GitHub Advanced Security SKUs.
#
# We model the configuration with two entries (neither using inheritance):
# - advanced_security.access: determines which access to give to child entries
# - advanced_security.entity_allowed: determines whether the entity is allowed access (when the parents permit).
module Configurable
  module AdvancedSecurityAccessPolicy
    extend T::Helpers
    requires_ancestor { Configurable }

    include Instrumentation::Model

    # This key represents the value entities inherit
    # and it'll take the form of one of the three keys below
    KEY = "advanced_security.access"

    ALL_ENTITIES = "all"
    SELECTED_ENTITIES = "selected"
    NO_ENTITIES = "none"

    # This key represents whether the entity has been enabled, however this might be overruled by a parent setting.
    ENTITY_KEY = "advanced_security.entity_allowed"

    ENTITY_ALLOWED_ALL = "true"
    ENTITY_ALLOWED_SECRET_PROTECTION_ONLY = "secret_protection_only"
    ENTITY_ALLOWED_CODE_SECURITY_ONLY = "code_security_only"
    ENTITY_ALLOWED_NONE = "false"

    ENTITY_ALLOWED_VALUES = [
      ENTITY_ALLOWED_ALL,
      ENTITY_ALLOWED_SECRET_PROTECTION_ONLY,
      ENTITY_ALLOWED_CODE_SECURITY_ONLY,
      ENTITY_ALLOWED_NONE,
    ].freeze

    def allow_members_to_enable_advanced_security(actor:)
      changed = config.set(KEY, ALL_ENTITIES, actor)
      instrument_advanced_security_policy(policy: ALL_ENTITIES, actor: actor) if changed
    end

    def allow_selected_members_to_enable_advanced_security(actor:)
      changed = config.set(KEY, SELECTED_ENTITIES, actor)
      instrument_advanced_security_policy(policy: SELECTED_ENTITIES, actor: actor) if changed
    end

    def disallow_members_to_enable_advanced_security(actor:)
      changed = config.set(KEY, NO_ENTITIES, actor)
      instrument_advanced_security_policy(policy: NO_ENTITIES, actor: actor) if changed
    end

    def all_members_can_enable_advanced_security?
      # Only the setting on the current entry matters, so we check for locality
      !config.local?(KEY) || config.get(KEY) == ALL_ENTITIES
    end

    def selected_members_can_enable_advanced_security?
      # Only the setting on the current entry matters, so we check for locality
      !!config.local?(KEY) && config.get(KEY) == SELECTED_ENTITIES
    end

    def no_members_can_enable_advanced_security?
      # Only the setting on the current entry matters, so we check for locality
      !!config.local?(KEY) && config.get(KEY) == NO_ENTITIES
    end

    def set_advanced_security_entity_policy(policy:, actor:)
      changed = config.set(ENTITY_KEY, policy, actor)
      instrument_advanced_security_entity_policy(policy: policy, actor: actor) if changed
    end

    # This answers the question of whether a specific entity is allowed to
    # toggle ghas on/off.
    def policy_allows_advanced_security_enablement?(sku: ENTITY_ALLOWED_ALL)
      effective_owner = effective_advanced_security_configuration_owner

      # If there is no owner then the entity is at top-level and is therefore allowed to change the policy
      return true if effective_owner.nil?

      # The owner needs access itself
      return false if !effective_owner.policy_allows_advanced_security_enablement?(sku: sku)
      # The owner does not allow members to enable ghas
      return false if effective_owner.no_members_can_enable_advanced_security?
      # The owner allows all members to enable ghas
      return true if effective_owner.all_members_can_enable_advanced_security?

      # Now that the owner has been checked, the entity itself determines whether access is allowed.
      return false if !config.local?(ENTITY_KEY)
      return true if config.get(ENTITY_KEY) == ENTITY_ALLOWED_ALL
      return true if config.get(ENTITY_KEY) == sku
      false
    end

    # Returns the policy for the current entity, not taking into account parent policies.
    def entity_advanced_security_policy
      return ENTITY_ALLOWED_NONE if !config.local?(ENTITY_KEY)
      config.get(ENTITY_KEY)
    end

    # Returns the list of child entities that have been enabled (not taking the parent policies into account)
    # This is only used in the pre-SKU split component, and can be removed when support for bundled GHAS SKUs is.
    def advanced_security_access_allowed_entities
      T.bind(self, T.any(Business, Organization))
      entries = []
      target_ids = []
      target_type = ""
      if self.is_a?(Business)
        target_ids = self.organization_ids
        target_type = "User"
      end
      if self.is_a?(Organization)
        target_ids = self.repository_ids
        target_type = "Repository"
      end

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

    # Returns the list of configuration entries for child entities that have an explicit policy set directly on them.
    def advanced_security_access_entity_policies
      T.bind(self, T.any(Business, Organization))
      entries = {}
      target_ids = []
      target_type = ""
      if self.is_a?(Business)
        target_ids = self.organization_ids
        target_type = "User"
      end
      if self.is_a?(Organization)
        target_ids = self.repository_ids
        target_type = "Repository"
      end

      if target_ids.present? && target_type.present?
        target_ids.each_slice(500) do |slice|
          ::Configuration::Entry
            .targeting_type(target_type)
            .named(ENTITY_KEY)
            .for_target_id(slice)
            .pluck(:target_id, :value)
            .each do |target_id, value|
              entries[target_id] = value
            end
        end
      end

      entries
    end

    # For testing
    def clear_members_to_enable_advanced_security(actor:)
      config.delete(KEY, actor)
    end

    private

    def effective_advanced_security_configuration_owner
      if configuration_owner.respond_to?(:policy_allows_advanced_security_enablement?)
        configuration_owner
      elsif configuration_owner&.configuration_owner.respond_to?(:policy_allows_advanced_security_enablement?)
        configuration_owner.configuration_owner
      end
    end

    def instrument_advanced_security_policy(policy:, actor:)
      self.instrument "advanced_security_policy_update", new_policy: policy, actor: actor
    end

    def instrument_advanced_security_entity_policy(policy:, actor:)
      # These two events are legacy events from before the SKUs were split.
      self.instrument("advanced_security_policy_selected_member_enabled", actor: actor) if policy == ENTITY_ALLOWED_ALL
      self.instrument("advanced_security_policy_selected_member_disabled", actor: actor) if policy == ENTITY_ALLOWED_NONE

      # To make the values in the audit log more user-friendly, we translate the legacy true and false values to more friendly names.
      audit_policy = case policy
      when ENTITY_ALLOWED_ALL
        "all"
      when ENTITY_ALLOWED_NONE
        "none"
      else
        policy
      end
      self.instrument("advanced_security_entity_policy_update", actor: actor, new_policy: audit_policy)
    end
  end
end
