# typed: true
# frozen_string_literal: true

module Configurable
  module MembersCanInviteOutsideCollaborators
    extend T::Helpers

    requires_ancestor { Configurable }

    # possible values of config and their meanings, default permissive (all invitations allowed):
    # no row for (key, object): config is not set at the level of the given object, inherit from parent
    # false for (key, object): child repo admins can invite outside collaborators to child repos
    # true for (key, object): only organization owners can invite outside collaborators to child repos
    # enterprise_admins_only for (key, object): only enterprise admins can invite outside collaborators to child repos
    #
    # no row: members_can_invite_outside_collaborators_policy? -> inherit (default false), allow_members_can_invite_outside_collaborators? -> inherit (default true), enterprise_admins_only_can_invite_outside_collaborators> -> inherit (default false)
    # false: members_can_invite_outside_collaborators_policy? -> true, allow_members_can_invite_outside_collaborators? -> true, enterprise_admins_only_can_invite_outside_collaborators> -> false
    # true: members_can_invite_outside_collaborators_policy? -> true, allow_members_can_invite_outside_collaborators? -> false, enterprise_admins_only_can_invite_outside_collaborators> -> false
    # enterprise_admins_only: members_can_invite_outside_collaborators_policy? -> true, allow_members_can_invite_outside_collaborators? -> false, enterprise_admins_only_can_invite_outside_collaborators> -> true
    KEY = "disable_members_can_invite_outside_collaborators".freeze

    ORG_ADMINS_ONLY = Configuration::TRUE
    ENTERPRISE_ADMINS_ONLY = "enterprise_admins_only".freeze
    MEMBERS_ALLOWED = false

    # DISALLOWED_VALUES = [ENTERPRISE_ADMINS_ONLY, ORG_ADMINS_ONLY].freeze


    # Enable the `members can invite collaborators` setting by making sure the
    # 'disable' key is either absent or set to false - need to set it to false
    # for cases where we want the setting to be inherited
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing
    def allow_members_can_invite_outside_collaborators(force: false, actor:)
      changed = if force
        # since the default is false, disabling the setting is equivalent to deleting,
        # but in order to enforce the value, the setting record needs to exist
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end
      return unless changed

      T.unsafe(self).instrument(
        :update_member_repository_invitation_permission,
        instrumentation_payload_for_invite_setting(actor)
      )
    end

    # Disable the `members can invite collaborators` setting by making sure the 'disable'
    # key is present
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing
    def disallow_members_can_invite_outside_collaborators(force: false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      T.unsafe(self).instrument(
        :update_member_repository_invitation_permission,
        instrumentation_payload_for_invite_setting(actor)
      )
    end

    # Similar but more restrictive to `disallow_members_can_invite_outside_collaborators`,
    # sets the config key to an alternate value. `#members_can_invite_outside_collaborators?` will return
    # `false`, and `#enterprise_admins_only_can_invite_outside_collaborators?` will return `true`.
    #
    # This value is intended to be set by Business admins at the Enterprise level and never overridden
    # for a given Org, hence it's a no-op if run on an Organization.
    # actor - user doing the action
    #
    # Returns nothing
    def enterprise_admins_only_can_invite_outside_collaborators(actor:, skip_log: false)
      return unless T.unsafe(self).is_a?(Business)

      changed = config.set!(KEY, ENTERPRISE_ADMINS_ONLY, actor, true)
      return unless changed

      unless skip_log
        T.unsafe(self).instrument(
          :update_member_repository_invitation_permission,
          instrumentation_payload_for_invite_setting(actor)
        )
      end
    end

    # Clear the `members can invite collaborators` setting for this object,
    # thus removing the default value for inheritance
    #
    # actor - user doing the action
    #
    # Returns nothing
    def clear_members_can_invite_outside_collaborators(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      T.unsafe(self).instrument(
        :clear_members_can_invite_outside_collaborators,
        instrumentation_payload_for_invite_setting(actor).except(:permission)
      )
    end

    # Retrieves the value for the `members can invite collaborators` setting
    # Automatically returns false if feature is disabled at the Instance level (GHE only)
    # Returns true if the setting isn't set for this object or
    # its parent. GitHub is the ultimate parent, but we never set the setting
    # at that level, only for Businesses and Organizations
    #
    # returns: Boolean
    def members_can_invite_outside_collaborators?
      policy_setting == :members
    end

    # Retrieves the value for the `members can invite collaborators` setting
    # Automatically returns false if feature is disabled at the Instance level (GHE only)
    #
    # returns: Boolean
    def enterprise_admins_only_can_invite_outside_collaborators?
      policy_setting == :enterprise_admins_only
    end

    # @return [Boolean] whether restricting repo invitations is allowed at all
    # true for all enterprise orgs
    # true for businesses and business orgs on the business_plus plan
    def can_restrict_repo_invites?
      GitHub.enterprise? ||
      T.unsafe(self).is_a?(Business) ||
        (T.unsafe(self).respond_to?(:business_plus?) && T.unsafe(self).business_plus?)
    end

    # Checks if this setting is enforced for all of this object's Configurable
    # children
    #
    # Returns: Boolean
    def members_can_invite_outside_collaborators_policy?
      !!config.final?(KEY)
    end

    # Checks if the setting is set for this object
    #
    # Returns: Boolean
    def members_can_invite_outside_collaborators_set?
      config.local?(KEY)
    end

    # Checks if the given actor can convert users to outside collaborators.
    # This is used on a few of the org people settings pages.
    # This check does not apply to a Business
    # Org admins can always convert users to outside collaborators if the org
    # does not belong to a business.
    def allow_conversion_to_outside_collaborator?(actor:)
      return false unless actor
      return false unless T.unsafe(self).is_a?(Organization)

      org = T.cast(self, Organization)
      if actor.can_have_granular_permissions?  # Different permission check for bots
        return false unless org.resources.members.writable_by?(actor)
      else  # Regular permission check for users
        return false unless org.adminable_by?(actor)
      end
      return true unless org.business.present?

      business = T.must(org.business)
      return false if business.enterprise_managed_user_enabled? && !business.emu_repository_collaborators_enabled?
      !business.enterprise_admins_only_can_invite_outside_collaborators? ||
        business.adminable_by?(actor)
    end

    private def instrumentation_payload_for_invite_setting(actor)
      payload = {
        actor: actor,
        permission: members_can_invite_outside_collaborators?,
      }

      if T.unsafe(self).is_a?(Organization)
        payload[:org] = self
        org = T.cast(self, Organization)
        payload[:business] = org.business if org.business
        payload[:emu] = org.enterprise_managed_user_enabled?
      elsif T.unsafe(self).is_a?(Business)
        payload[:business] = self
        payload[:emu] = T.cast(self, Business).enterprise_managed_user_enabled?
      end

      payload
    end

    private def policy_setting
      return :members unless can_restrict_repo_invites?

      case config.get(KEY)
      when nil # no row
        :members
      when MEMBERS_ALLOWED # boolean false
        :members
      when ORG_ADMINS_ONLY # string "true"
        :org_admins
      when ENTERPRISE_ADMINS_ONLY # string "enterprise_admins_only"
        :enterprise_admins_only
      end
    end
  end
end
