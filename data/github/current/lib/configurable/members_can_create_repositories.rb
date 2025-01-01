# typed: true
# frozen_string_literal: true

module Configurable
  module MembersCanCreateRepositories
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "disable_members_can_create_repositories".freeze

    ALL           = "all".freeze                # prevent members from creating any repositories
    PUBLIC        = "public".freeze             # prevent members from creating public repositories, but allow private and internal
    NONE          = "none".freeze               # don't prevent members from creating any repositories
    ALL_ALIASES   = [ALL, "1", "true"].freeze   # legacy values that are equivalent to ALL
    NONE_ALIASES  = [NONE, "0", "false"].freeze # legacy values that are equivalent to ALL
    PRIVATE       = "private".freeze            # prevent members from creating private repositories, but allow public and internal

    # More granular config settings now that internal repositories exist
    # The config keys represent what is _disallowed_
    INTERNAL         = "internal".freeze         # Public + private repos allowed
    PUBLIC_INTERNAL  = "public_internal".freeze  # Private repos allowed
    PRIVATE_INTERNAL = "private_internal".freeze # Public repos allowed
    PUBLIC_PRIVATE   = "public_private".freeze   # Internal repos allowed

    GRANULAR_REPO_RESTRICTION_VALUES = [PUBLIC, INTERNAL, PRIVATE, PUBLIC_INTERNAL, PRIVATE_INTERNAL, PUBLIC_PRIVATE]

    PUBLIC_DISALLOWED_VALUES = [ALL_ALIASES, PUBLIC, PUBLIC_INTERNAL, PUBLIC_PRIVATE].flatten.freeze
    PRIVATE_DISALLOWED_VALUES = [ALL_ALIASES, PRIVATE, PUBLIC_PRIVATE, PRIVATE_INTERNAL].flatten.freeze
    INTERNAL_DISALLOWED_VALUES = [ALL_ALIASES, INTERNAL, PUBLIC_INTERNAL, PRIVATE_INTERNAL].flatten.freeze

    VALID_VALUES = [ALL_ALIASES, NONE_ALIASES, *GRANULAR_REPO_RESTRICTION_VALUES].flatten.freeze

    # @return [Boolean] whether restricting public repo creation is allowed at all
    # true for all enterprise orgs
    # true for businesses and business orgs
    #
    # NOTE: When true, this means public repo creation cannot be restricted BY ITSELF. All orgs are
    #       allowed to disable creation of ALL repos and/or PRIVATE repos. This is further
    #        complicated by the addition of internal repositories:
    #
    # Allowed for all:
    #   Disable ALL
    #   Disable PRIVATE
    #   DISABLE PRIVATE and INTERNAL (internal are available to only enterprise, so this isn't meaningful but technically true)
    #
    # Allowed only for enterprise orgs (the plan for which is now called business_plus):
    #   Disable ALL
    #   Disable any individual combination of PUBLIC/PRIVATE/INTERNAL
    def can_restrict_only_public_repo_creation?
      return true if GitHub.enterprise?
      self.respond_to?(:business_plus?) ? T.unsafe(self).business_plus? : true
    end

    # Called on Organizations when they downgrade from the business_plus plan.
    # Changes the configuration value to ALL if it previously included PUBLIC
    # (but was not ALL).
    #
    # actor - The User that initiated the plan downgrade.
    #
    # Returns nothing.
    def restrict_public_repo_creation_plan_downgrade(actor:)
      changed = if [PUBLIC, PUBLIC_INTERNAL, PUBLIC_PRIVATE].include?(config.get(KEY))
        config.set!(KEY, ALL, actor, false)
      end
      return unless changed

      T.unsafe(self).instrument(:update_member_repository_creation_permission,
                 instrumentation_payload_for_create_setting(actor))
    end

    # Enable the `members can create repositories` setting by making sure the
    # 'disable' key is either absent or set to NONE - need to set it to NONE
    # for cases where we want the setting to be inherited
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing
    def allow_members_can_create_repositories(force: false, actor:)
      changed = if force
        # since the default is false, disabling the setting is equivalent to deleting,
        # but in order to enforce the value, the setting record needs to exist
        config.set!(KEY, NONE, actor, force)
      else
        config.delete(KEY, actor)
      end
      return unless changed

      T.unsafe(self).instrument(:update_member_repository_creation_permission,
                 instrumentation_payload_for_create_setting(actor))
    end

    # Disable the `members can create public repositories` setting by making sure the 'disable'
    # key is set to PUBLIC
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing
    def disallow_members_can_create_public_repositories(force: false, actor:)
      check_public_repo_creation_restriction(public_visibility: false, private_visibility: true, internal_visibility: true)
      changed = config.set!(KEY, PUBLIC, actor, force)
      return unless changed

      T.unsafe(self).instrument(:update_member_repository_creation_permission,
                 instrumentation_payload_for_create_setting(actor))
    end

    # Disable the `members can create repositories` setting by making sure the 'disable'
    # key is set to ALL
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing
    def disallow_members_can_create_repositories(force: false, actor:)
      changed = config.set!(KEY, ALL, actor, force)
      return unless changed

      T.unsafe(self).instrument(:update_member_repository_creation_permission,
                 instrumentation_payload_for_create_setting(actor))
    end

    # Update the `members can create repositories` setting to the given value
    #
    # DEPRECATED: Now used only for API backward-compatibility.
    # Prefer `allow_members_can_create_repositories_with_visibilities`.
    #
    #   Note that the setting passed here is the opposite of what is stored in "disable_members_can_create_repositories".
    #   We store the types that members are restricted from creating, instead of what they are allowed to create.
    #
    # setting - the new value. Valid values are:
    #   "all"     - members can create repos with any visibility. ("1" and "true" are aliases for "all")
    #   "none"    - members cannot create repos of any visibility.  ("0" and "false" are aliases for "none")
    #   "private" - members can only create private repos.
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing - raise ArgumentError if an invalid value is passed in
    def update_members_can_create_repositories(setting, force: false, actor:)
      case setting.to_s
      when *ALL_ALIASES
        allow_members_can_create_repositories(force: force, actor: actor)
      when PRIVATE
        disallow_members_can_create_public_repositories(force: force, actor: actor)
      when *NONE_ALIASES
        disallow_members_can_create_repositories(force: force, actor: actor)
      else
        raise ArgumentError
      end
    end

    # Allow members to create repositories of specified visibilities.
    #
    #   Note that the setting passed here is the opposite of what is stored in "disable_members_can_create_repositories".
    #   We store the types that members are restricted from creating, instead of what they are allowed to create.
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns an array of visibility types that are actually enabled, accounting for org and plan
    # rules, e.g. whether an org is allowed to restrict public repo creation.
    def allow_members_can_create_repositories_with_visibilities(force: false, actor:, public_visibility: nil, private_visibility: nil, internal_visibility: nil)
      check_public_repo_creation_restriction(public_visibility: public_visibility, private_visibility: private_visibility, internal_visibility: internal_visibility)

      # Retrieve current setting to avoid changing any visibilities not provided
      public_visibility = members_can_create_public_repositories? if public_visibility.nil?
      private_visibility = members_can_create_private_repositories? if private_visibility.nil?
      internal_visibility = members_can_create_internal_repositories? if internal_visibility.nil?

      # These values are inversed because the key we store represents what is disallowed
      public_value = public_visibility ? nil : PUBLIC
      private_value = private_visibility ? nil : PRIVATE
      internal_value = internal_visibility ? nil : INTERNAL
      config_value = [public_value, private_value, internal_value].reject(&:blank?).join("_")
      if config_value == ""
        config_value = NONE
      elsif config_value == "public_private_internal"
        config_value = ALL
      end
      changed = config.set!(KEY, config_value, actor, force)

      T.unsafe(self).instrument(:update_member_repository_creation_permission,
                 instrumentation_payload_for_create_setting(actor)) if changed

      # There are rules around repo creation that supercede what might be set
      # here, so we return the effective enabled repository types.
      enabled = []
      enabled << "public" if members_can_create_public_repositories?
      enabled << "private" if members_can_create_private_repositories?
      enabled << "internal" if members_can_create_internal_repositories?
      enabled
    end

    class PublicRepoCreationRestricted < StandardError; end

    # Checks whether the caller is allowed to restrict public repo creation based on the public/private/internal values being passed.
    # It returns nil if all is well and raises if violating policy.
    #
    # Only enterprise orgs are allowed to turn of ONLY public repo creation.
    # Everybody can turn off all repo creation.
    # Full details are in the comment for `can_restrict_only_public_repo_creation?`.
    #
    # This method is concerned with what does "all repos" mean for an org. If they don't have access
    # to internal repos, the `internal_visibility` value provided is irrelevant.
    private def check_public_repo_creation_restriction(public_visibility:, private_visibility:, internal_visibility:)
      # Disallow non-enterprise orgs from restricting only public repo creation as described in can_restrict_only_public_repo_creation?
      return if can_restrict_only_public_repo_creation?
      if !T.unsafe(self).supports_internal_repositories?
        return if !private_visibility
        return if public_visibility && private_visibility
      end
      # This _should_ never be hit, as orgs with access to internal repos should always allow public repo restriction,
      # but this is here in the event an org somehow maintains its enterprise association without a matching plan.
      return if !private_visibility && !internal_visibility
      return if public_visibility && private_visibility && internal_visibility
      raise PublicRepoCreationRestricted, "Public repo creation cannot be restricted by itself."
    end

    # Returns the visibilities allowed when members create repos.
    #
    # DEPRECATED: Now used only for API backward-compatibility. Note that any combinations involving internal repos
    #             are not correctly handled by this method. In the future we'll ship a breaking change to the API
    #             that will allow us to remove this method!
    #
    # New code should call `members_can_create_[public|private|internal]_repositories?`.
    def members_allowed_repository_creation_type
      if members_can_create_public_repositories? && members_can_create_private_repositories?
        ALL
      elsif members_can_create_public_repositories?
        PUBLIC
      elsif members_can_create_private_repositories?
        PRIVATE
      else
        NONE
      end
    end

    # Clear the `members can create repositories` setting for this object,
    # thus removing the default value for inheritance
    #
    # actor - user doing the action
    #
    # Returns nothing
    def clear_members_can_create_repositories(actor:)
      changed = config.delete(KEY, actor)

      return unless changed

      T.unsafe(self).instrument(:clear_members_can_create_repos,
                 instrumentation_payload_for_create_setting(actor).except(:permission))
    end

    # Retrieves the value for the `members can create public repositories` setting
    # Returns true if the setting isn't set for this object or
    # its parent. GitHub is the ultimate parent, but we never set the setting
    # at that level, only for Businesses and Organizations
    #
    # returns: Boolean
    def members_can_create_public_repositories?
      # Prevent orgs from restricting public repo creation even if the config value was somehow allowed.
      return true if !can_restrict_only_public_repo_creation? && config.get(KEY) == PUBLIC
      # if the key isn't set at all, default to true
      !PUBLIC_DISALLOWED_VALUES.include?(config.get(KEY))
    end

    # Retrieves the value for the `members can create private repositories` setting
    # Returns true if the setting isn't set for this object or its parent.
    #
    # returns: Boolean
    def members_can_create_private_repositories?
      !PRIVATE_DISALLOWED_VALUES.include?(config.get(KEY))
    end

    # Retrieves the value for the `members can create internal repositories` setting
    # Returns true if the setting isn't set for this object or its parent.
    #
    # returns: Boolean
    def members_can_create_internal_repositories?
      return false unless T.unsafe(self).supports_internal_repositories?
      !INTERNAL_DISALLOWED_VALUES.include?(config.get(KEY))
    end

    # Returns whether there are any repository visibilities that may be created.
    #
    # returns: Boolean
    def members_can_create_repositories?
      members_can_create_public_repositories? || members_can_create_private_repositories? || members_can_create_internal_repositories?
    end

    # Checks if this setting is enforced for all of this object's Configurable
    # children
    #
    # Returns: Boolean
    def members_can_create_repositories_policy?
      !!config.final?(KEY)
    end

    def self.valid_permission_value?(value)
      VALID_VALUES.include?(value.to_s)
    end

    private

    # Private: returns the instrumentation payload for the current change
    # Fields set:
    #   - actor
    #   - permission (true/false)
    #   - visibility (none, all, combinations of public/private/internal)
    #   - business (if changing a business setting, or setting of an org which
    #               belongs to a Business)
    #   - org (if changing an org setting)
    #
    #  Parameters:
    #   actor - user making the change
    #
    # Returns: hash of parameters for instrumentation
    def instrumentation_payload_for_create_setting(actor)
      payload = {
        actor: actor,
        permission: members_can_create_repositories?,
        visibility: config.get(KEY),
      }

      if self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
