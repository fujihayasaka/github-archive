# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsAccess
    KEY = "actions_access"

    ALL_ENTITIES = "all"
    SELECTED_ENTITIES = "selected"
    NO_ENTITIES = "none"

    VALUES = [ALL_ENTITIES, SELECTED_ENTITIES, NO_ENTITIES]
    DEFAULT_VALUE = ALL_ENTITIES

    # the higher the number, the more restrictive the access
    HIERARCHY = {
      ALL_ENTITIES => 0,
      SELECTED_ENTITIES => 1,
      NO_ENTITIES => 2,
    }

    def enable_actions(actor:)
      config.set!(KEY, ALL_ENTITIES, actor, false)
    end

    def enable_actions_for_selected(actor:)
      config.set!(KEY, SELECTED_ENTITIES, actor, false)
    end

    def disable_actions(actor:)
      config.set!(KEY, NO_ENTITIES, actor)
    end

    # Returns the _effective_ Actions access policy.
    #
    # This means that instead of returning exactly what was configured for this
    # entity, we will also take the entity owner's policy into account.
    #
    # Between the default policy, the entity's policy, and the owner's
    # (normalized) policy, we'll return whichever is the most restrictive.
    #
    # The policy is automatically NO_ENTITIES if the owner chain has not permitted
    # this particular entity to run actions.
    def actions_access
      return NO_ENTITIES if actions_disabled_by_owner?

      raw_value = config.get(KEY)
      possibilities = [DEFAULT_VALUE]

      # Add its own setting as an option.
      possibilities << raw_value if config.local?(KEY)

      # This means that the setting has been inherited from its parent, which
      # means this entity should just follow suit.
      #
      # If we've reached this point, it means that this entity _is_ allowed to
      # run actions. In that case, we don't really care about the "for selected"
      # part of the owner's policy so let's normalize this to a simple disable
      # or enable option.
      possibilities << map_to_enable_or_disable(raw_value) if config.inherited?(KEY)
      possibilities.compact.max_by { |p| HIERARCHY[p] }
    end

    def actions_enabled_for_all_entities?
      actions_access == ALL_ENTITIES
    end

    def actions_enabled_for_selected_entities?
      actions_access == SELECTED_ENTITIES
    end

    def actions_disabled?
      actions_access == NO_ENTITIES
    end

    def actions_disabled_by_owner?
      if emu_actions_tab_policy_enabled?
        if self.is_a?(Repository) && T.must(self.owner).user? && self.is_enterprise_managed? && self.repo_self_hosted_runners_disabled_by_owner?
          return true
        end
      end
      owner_actions_access == NO_ENTITIES ||
      !!(owner_allows_actions_for_selected_entities? && !actions_allowed_by_owner?)
    end

    private

    def owner_allows_actions_for_selected_entities?
      effective_configuration_owner&.actions_enabled_for_selected_entities?
    end

    def map_to_enable_or_disable(policy)
      policy == NO_ENTITIES ? NO_ENTITIES : ALL_ENTITIES
    end

    def owner_actions_access
      effective_configuration_owner&.actions_access
    end

    def effective_configuration_owner
      if configuration_owner.respond_to?(:actions_access)
        configuration_owner
      elsif configuration_owner&.configuration_owner.respond_to?(:actions_access)
        configuration_owner.configuration_owner
      end
    end

    def emu_actions_tab_policy_enabled?
      billing_entity = get_billing_owner_from_entity

      FeatureFlag.vexi.enabled?(:emu_actions_tab_policy, billing_entity, default: false) ||
      FeatureFlag.vexi.enabled?(:emu_actions_tab_policy, default: false)
    end
  end
end
