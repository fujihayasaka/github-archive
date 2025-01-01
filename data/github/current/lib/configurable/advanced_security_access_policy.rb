# typed: true
# frozen_string_literal: true

# These configuration entries specifies whether repository admins are allowed
# to enable GitHub Advanced Security.
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

    def allow_enable_advanced_security(actor:)
      changed = config.enable(ENTITY_KEY, actor)
      instrument_advanced_security_entity(action: "enabled", actor: actor) if changed
    end

    def disallow_enable_advanced_security(actor:)
      changed = config.disable(ENTITY_KEY, actor)
      instrument_advanced_security_entity(action: "disabled", actor: actor) if changed
    end

    # This answers the question of whether a specific entity is allowed to
    # toggle ghas on/off.
    def policy_allows_advanced_security_enablement?
      effective_owner = effective_advanced_security_configuration_owner

      # If there is no owner then the entity is at top-level and is therefore allowed to change the policy
      return true if effective_owner.nil?

      # The owner needs access itself
      return false if !effective_owner.policy_allows_advanced_security_enablement?
      # The owner does not allow members to enable ghas
      return false if effective_owner.no_members_can_enable_advanced_security?
      # The owner allows all members to enable ghas
      return true if effective_owner.all_members_can_enable_advanced_security?

      # Now that the owner has been checked, the entity itself determines whether access is allows
      !!config.local?(ENTITY_KEY) && config.enabled?(ENTITY_KEY)
    end

    # Returns the list of child entities that have been enabled (not taking the parent policies into account)
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

    def instrument_advanced_security_entity(action:, actor:)
      self.instrument ("advanced_security_policy_selected_member_" + action), actor: actor
    end
  end
end
