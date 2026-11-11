# typed: true
# frozen_string_literal: true

module Configurable
  module ForcePushRejection
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    # Public: Indicate level of force-push rejection
    #
    # Returns String or false
    # (see #set_force_push_rejection for explanation of return values)
    def force_push_rejection
      config.get("git.reject_force_push") || false
    end

    # Public: Indicate level of force-push rejection
    #
    # Returns String or 'false' or nil (nil means value is not set)
    # (see #set_force_push_rejection for explanation of return values)
    def force_push_rejection_original_value
      config.raw("git.reject_force_push")
    end

    # Public: Set level of force-push rejection
    #
    # Acceptable values:
    #   false     - no rejection
    #   "default" - only reject force pushes to the default branch
    #   "all"     - reject all force pushes
    #
    # user - User setting the value
    #
    # Returns nothing
    def set_force_push_rejection(value, user, policy = false)
      unless [false, "false", "default", "all"].include?(value)
        raise TypeError, "force-push rejection value #{value.inspect} unknown"
      end

      config.set!("git.reject_force_push", value.to_s, user, policy)
    end

    # Public: Clear force-push rejection
    #
    # Removes the configuration setting entirely
    #
    # user - User clearing the value
    #
    # Returns nothing
    def clear_force_push_rejection(user)
      config.delete("git.reject_force_push", user)
    end

    # Public: Indicate if force-push settings can be changed on this object
    #
    # Returns true or false
    def force_push_rejection_writable?
      config.writable?("git.reject_force_push")
    end

    # Public: Indicate if force-push came from higher level via policy
    #
    # Returns true or false
    def force_push_rejection_policy?
      config.final?("git.reject_force_push")
    end

    # Public: Let us know if force-push rejection is set somewhere else
    #
    # Returns a Boolean
    def force_push_rejection_inherited?
      config.inherited?("git.reject_force_push")
    end

    # Public: Let us know if force-push rejection is set on this object
    #
    # Returns a Boolean
    def force_push_rejection_local?
      config.local?("git.reject_force_push")
    end

    # Public: Retrieve the object that has the force rejection value set
    #
    # Returns an a Configurable or nil
    def force_push_rejection_source
      config.source("git.reject_force_push")
    end

    # Public: Where a default value would come from if current setting is cleared.
    #
    # Returns a Configurable or nil
    def force_push_rejection_default_source
      configuration_default_entry_owner("git.reject_force_push")
    end

    # Public: Where a default value would come from if current setting is cleared.
    #
    # Returns a string or nil
    def force_push_rejection_default_value
      configuration_default_entry_value("git.reject_force_push")
    end
  end
end
