# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    # Public: Get a git configuration value.
    #
    # name - the String config option name.
    #
    # Returns the String option value, or nil if the option is not set.
    def config_get(name)
      send_message(:config_get, name)
    end

    # Public: Add or update a git configuration value.
    # DANGER: This updates hard state and must not be called directly.
    # Use GitHub::DGit::Util.config_store which does the proper locking.
    #
    # name - the String config option name.
    # value - the config option value, which must be a String, Integer,
    #         or true/false value.
    #
    # Returns the new option value.
    def config_store(name, value)
      send_message(:config_store, name, value)
    end

    # Public: Delete a git configuration value.
    # DANGER: This updates hard state and must not be called directly.
    # Use GitHub::DGit::Util.config_delete which does the proper locking.
    #
    # name - the String config option name.
    #
    # Returns true if the option was present, or false otherwise.
    def config_delete(name)
      send_message(:config_delete, name)
    end
  end
end
