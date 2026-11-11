# typed: true
# frozen_string_literal: true

module Configurable
  module MaxObjectSize
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    DEFAULT_MAX_OBJECT_SIZE = 100

    # Public: Gets current max object size in MB, 0 means no limit
    #
    # Returns Integer
    def max_object_size
      config.get("git.maxobjectsize").try(:to_i) || DEFAULT_MAX_OBJECT_SIZE
    end

    def default_max_object_size
      DEFAULT_MAX_OBJECT_SIZE
    end

    # Public: Set Max Object Size for git pushes
    #
    # Acceptable values:
    #   0 means no size limit.
    #   Any other integer is a limit in MB.
    #
    # To clear the setting, use #clear_max_object_size instead.
    #
    # user - User setting the value
    #
    # Returns nothing
    def set_max_object_size(value, user, policy = false)
      begin
        int_val = Integer(value)
      rescue ArgumentError
        raise ArgumentError, "Value must be an integer"
      end

      config.set!("git.maxobjectsize", value.to_i, user, policy)
    end

    # Public: Clear force-push rejection
    #
    # Removes the configuration setting entirely
    #
    # user - User clearing the value
    #
    # Returns nothing
    def clear_max_object_size(user)
      config.delete("git.maxobjectsize", user)
    end

    # Public: Indicate if maxobjectsize settings can be changed on this object
    #
    # Returns true or false
    def max_object_size_writable?
      config.writable?("git.maxobjectsize")
    end

    # Public: Indicate if maxobjectsize came from higher level via policy
    #
    # Returns true or false
    def max_object_size_policy?
      config.final?("git.maxobjectsize")
    end

    # Public: Let us know if maxobjectsize is set somewhere else
    #
    # Returns a Boolean
    def max_object_size_inherited?
      config.inherited?("git.maxobjectsize")
    end

    # Public: Let us know if maxobjectsize is set on this object
    #
    # Returns a Boolean
    def max_object_size_local?
      config.local?("git.maxobjectsize")
    end

    # Public: Retrieve the object that has the force rejection value set
    #
    # Returns a Configurable or nil
    def max_object_size_source
      config.source("git.maxobjectsize")
    end

    # Public: Where a default value would come from if current setting is cleared.
    #
    # Returns a Configurable or nil
    def max_object_size_default_source
      configuration_default_entry_owner("git.maxobjectsize")
    end

    # Public: Where a default value would come from if current setting is cleared.
    #
    # Returns a string or nil
    def max_object_size_default_value
      configuration_default_entry_value("git.maxobjectsize")
    end
  end
end
