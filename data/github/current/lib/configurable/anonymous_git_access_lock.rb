# typed: false
# frozen_string_literal: true

module Configurable
  module AnonymousGitAccessLock
    KEY = "anonymous_git_access_locked".freeze

    # Lock anonymous git access.  Only site admins will be able to update
    # anonymous git access.
    def lock_anonymous_git_access(actor, force: false)
      changed = config.enable!(KEY, actor, force)

      return unless changed
      instrument_anonymous_git_access_lock(:lock_anonymous_git_access, actor)
    end

    # Unlock the setting.  Site admins and repository admins will be able
    # to update anonymous git access.
    def unlock_anonymous_git_access(actor)
      changed = config.delete(KEY, actor)

      return unless changed
      instrument_anonymous_git_access_lock(:unlock_anonymous_git_access, actor)
    end

    # Determine whether anonymous git access can be changed for a user.
    # Can call without a user argument to get the configured value.
    def anonymous_git_access_locked?(actor = nil)
      config.enabled?(KEY) && !actor&.site_admin?
    end

    # Determine whether anonymous git access setting is locked
    # by an enforced policy
    def anonymous_git_access_locked_policy?
      !!config.final?(KEY)
    end

    private

    # Instrument anonymous git access lock changes
    #
    # event - the event name
    # actor - the User locking anonymous git access
    #
    # Returns: nothing
    def instrument_anonymous_git_access_lock(event, actor)
      payload = { actor: actor }

      if self.is_a?(Repository)
        target = "repo"
        payload[:repo] = self
        payload[:org] = organization if in_organization?
      else
        target = "enterprise"
      end

      GitHub.instrument("#{target}.config.#{event}", payload)
    end
  end
end
