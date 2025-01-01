# typed: true
# frozen_string_literal: true

module Configurable
  module MembersCanDeleteRepositories
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "disable_members_can_delete_repositories".freeze

    # Enable the `members can delete repositories` setting by making sure the
    # 'disable' key is either absent or set to false - need to set it to false
    # for cases where we want the setting to be inherited
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing
    def allow_members_can_delete_repositories(force: false, actor:)
      changed = if force
        # since the default is false, disabling the setting is equivalent to deleting,
        # but in order to enforce the value, the setting record needs to exist
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("members_can_delete_repos.enable")
      GitHub.instrument(
          "members_can_delete_repos.enable",
          instrumentation_payload(actor))
    end

    # Disable the `members can delete repositories` setting by making sure the 'disable'
    # key is present
    #
    # force - force the setting to override the settings on any child objects
    # actor - user doing the action
    #
    # Returns nothing
    def disallow_members_can_delete_repositories(force: false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("members_can_delete_repos.disable")
      GitHub.instrument(
          "members_can_delete_repos.disable",
          instrumentation_payload(actor))
    end

    # Clear the `members can delete repositories` setting for this object,
    # thus removing the default value for inheritance
    #
    # actor - user doing the action
    #
    # Returns nothing
    def clear_members_can_delete_repositories(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("members_can_delete_repos.clear")
      GitHub.instrument(
          "members_can_delete_repos.clear",
          instrumentation_payload(actor))
    end

    # Retrieves the value for the `members can delete repositories` setting
    # Automatically returns false if feature is disabled at the Instance level (GHE only)
    # Returns true if the setting isn't set for this object or
    # its parent. GitHub is the ultimate parent, but we never set the setting
    # at that level, only for Businesses and Organizations
    #
    # returns: Boolean
    def members_can_delete_repositories?
      # return true unless the key is set to true. Key not being set at all
      # defaults to true
      !config.enabled?(KEY)
    end

    # Checks if this setting is enforced for all of this object's Configurable
    # children
    #
    # Returns: Boolean
    def members_can_delete_repositories_policy?
      !!config.final?(KEY)
    end

    private def instrumentation_payload(actor)
      payload = { user: actor }

      if T.unsafe(self).is_a?(Organization)
        payload[:org] = self
        payload[:business] = T.cast(self, Organization).business if T.cast(self, Organization).business
      elsif T.unsafe(self).is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
