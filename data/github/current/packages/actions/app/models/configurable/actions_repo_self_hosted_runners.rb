# typed: strict
# frozen_string_literal: true

# Whether repositories are allowed to use self-hosted runners. It can be configured
# by enterprise and organization admins and is enabled by default.
module Configurable
  module ActionsRepoSelfHostedRunners
    include Instrumentation::Model
    include Kernel

    extend T::Helpers

    requires_ancestor { Configurable }

    ENABLE_KEY = "repo_self_hosted_runners_enabled"
    ENABLE_EMUS_KEY = "repo_self_hosted_runners_enabled_for_emus"
    ALLOW_KEY = "repo_self_hosted_runners_allowed_by_owner"

    ALL_ENTITIES = T.let("all".freeze, String)
    NO_ENTITIES = T.let("none".freeze, String)
    SELECTED_ENTITIES = T.let("selected".freeze, String)

    VALUES = T.let([ALL_ENTITIES, NO_ENTITIES, SELECTED_ENTITIES].freeze, T::Array[String])
    DEFAULT_VALUE = ALL_ENTITIES
    ALLOWED_VALUES_FOR_ENTERPRISE = T.let([ALL_ENTITIES, NO_ENTITIES].freeze, T::Array[String])

    sig { returns(T::Boolean) }
    def repo_self_hosted_runners_enabled_for_all_entities?
      repo_self_hosted_runners_access == ALL_ENTITIES
    end

    sig { returns(T::Boolean) }
    def repo_self_hosted_runners_enabled_for_selected_entities?
      repo_self_hosted_runners_access == SELECTED_ENTITIES
    end

    sig { returns(T::Boolean) }
    def repo_self_hosted_runners_disabled?
      repo_self_hosted_runners_access == NO_ENTITIES
    end

    sig { returns(T::Boolean) }
    def repo_self_hosted_runners_enabled_for_emus?
      return false unless self.is_a?(Business)

      return true unless !!config.local?(ENABLE_EMUS_KEY)
      config.enabled?(ENABLE_EMUS_KEY)
    end

    sig { returns(String) }
    def repo_self_hosted_runners_access
      return NO_ENTITIES if repo_self_hosted_runners_disabled_by_owner?

      config.get(ENABLE_KEY) || DEFAULT_VALUE
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_repo_self_hosted_runners(actor:)
      # Calling config.set! with final set to false (last argument) will
      # allow children in the hierarchy to override the policy value.
      old_policy = repo_self_hosted_runners_access
      updated = config.set!(ENABLE_KEY, ALL_ENTITIES, actor, false)
      instrument "update_repo_self_hosted_runners_policy", {
        old_repo_runners_policy: old_policy,
        new_repo_runners_policy: repo_self_hosted_runners_access,
        actor: actor,
      } if updated
      updated
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_repo_self_hosted_runners_for_selected_entities(actor:)
      # Calling config.set! with final set to false (last argument) will
      # allow children in the hierarchy to override the policy value.
      old_policy = repo_self_hosted_runners_access
      updated = config.set!(ENABLE_KEY, SELECTED_ENTITIES, actor, false)
      instrument "update_repo_self_hosted_runners_policy", {
        old_repo_runners_policy: old_policy,
        new_repo_runners_policy: repo_self_hosted_runners_access,
        actor: actor,
      } if updated
      updated
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_repo_self_hosted_runners_for_emus(actor:)
      old_emu_policy = repo_self_hosted_runners_enabled_for_emus?
      updated = config.enable!(ENABLE_EMUS_KEY, actor)
      instrument "update_emu_repo_self_hosted_runners_policy", {
        old_emu_repo_runners_policy: convert_emu_policy_to_string(old_emu_policy),
        new_emu_repo_runners_policy: convert_emu_policy_to_string(repo_self_hosted_runners_enabled_for_emus?),
        actor: actor,
      } if updated
      updated
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disable_repo_self_hosted_runners(actor:)
      # Calling config.set! with final set to true (last argument) will
      # override the policy value for any children in the hierarchy.
      old_policy = repo_self_hosted_runners_access
      updated = config.set!(ENABLE_KEY, NO_ENTITIES, actor, true)
      instrument "update_repo_self_hosted_runners_policy", {
        old_repo_runners_policy: old_policy,
        new_repo_runners_policy: repo_self_hosted_runners_access,
        actor: actor,
      } if updated
      updated
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disable_repo_self_hosted_runners_for_emus(actor:)
      old_emu_policy = repo_self_hosted_runners_enabled_for_emus?
      updated = config.disable!(ENABLE_EMUS_KEY, actor)
      instrument "update_emu_repo_self_hosted_runners_policy", {
        old_emu_repo_runners_policy: convert_emu_policy_to_string(old_emu_policy),
        new_emu_repo_runners_policy: convert_emu_policy_to_string(repo_self_hosted_runners_enabled_for_emus?),
        actor: actor,
      } if updated
      updated
    end

    sig { params(emu_policy: T::Boolean).returns(String) }
    def convert_emu_policy_to_string(emu_policy)
      return ALL_ENTITIES if emu_policy
      NO_ENTITIES
    end

    sig { returns(T::Boolean) }
    def repo_self_hosted_runners_disabled_by_owner?
      return false if self.is_a?(Business)
      if self.is_a?(Repository) && self.is_enterprise_managed? && T.must(self.owner).user?
        return !T.must(self.owner).enterprise_managed_business.repo_self_hosted_runners_enabled_for_emus?
      end
      owner = effective_repo_self_hosted_runners_access_configuration_owner
      owner&.repo_self_hosted_runners_disabled? ||
        # If the owner enabled runners for selected entities this entity must
        # have been explicitly allowed.
        !!(owner&.repo_self_hosted_runners_enabled_for_selected_entities? && !repo_self_hosted_runners_allowed_by_owner?)
    end

    sig { returns(T::Array[Integer]) }
    def repo_self_hosted_runners_allowed_entities
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
            .named(ALLOW_KEY)
            .with_true_value
            .for_target_id(slice)
            .pluck(:target_id)
        end
      end

      entries
    end

    sig { params(actor: User).returns(T::Boolean) }
    def allow_repo_self_hosted_runners(actor:)
      config.enable(ALLOW_KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disallow_repo_self_hosted_runners(actor:)
      config.disable(ALLOW_KEY, actor)
    end

    # used for testing
    sig { params(actor: User).returns(T::Boolean) }
    def clear_repo_self_hosted_runners_allowed(actor:)
      config.delete(ALLOW_KEY, actor)
    end

    # This means that the setting has to be explicitly set to `true` in order to
    # be considered enabled. `nil` is equivalent to `false`. Inherited values are ignored.
    sig { returns(T::Boolean) }
    def repo_self_hosted_runners_allowed_by_owner?
      !!config.local?(ALLOW_KEY) && config.enabled?(ALLOW_KEY)
    end

    sig { returns(T.any(Business, Organization, NilClass)) }
    def effective_repo_self_hosted_runners_access_configuration_owner
      if configuration_owner.respond_to?(:repo_self_hosted_runners_access)
        configuration_owner
      elsif configuration_owner&.configuration_owner.respond_to?(:repo_self_hosted_runners_access)
        configuration_owner.configuration_owner
      end
    end

    sig { returns(T.any(Business, Organization, User, NilClass)) }
    def get_billing_owner_from_entity
      if self.is_a?(Repository)
        return nil if self.owner.nil?
        return T.must(self.owner).billable_owner
      end
      if self.is_a?(Business)
        return self.billable_owner
      end
      if self.is_a?(Organization)
        return self.billable_owner
      end
      nil
    end
  end
end
