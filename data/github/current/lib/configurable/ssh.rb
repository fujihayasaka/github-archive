# typed: true
# frozen_string_literal: true

module Configurable
  module Ssh
    extend T::Helpers

    requires_ancestor { Configurable }

    FALSE = "false".freeze
    TRUE  = "true".freeze

    def enable_ssh(actor, policy = false)
      config.set!("ssh_enabled", TRUE, actor, policy)
    end

    def disable_ssh(actor, policy = false)
      config.set!("ssh_enabled", FALSE, actor, policy)
    end

    def clear_ssh(actor)
      config.delete("ssh_enabled", actor)
    end

    # Public: Can repositories be accessed by SSH? Default is true.
    def ssh_enabled?
      ssh_enabled = config.get("ssh_enabled")
      ssh_enabled.nil? ? true : ssh_enabled
    end

    # Public: Get original value of ssh config.
    def ssh_enabled_original_value
      config.raw("ssh_enabled")
    end

    # Public: Indicate if ssh settings can be changed on this object
    #
    # Returns true or false
    def ssh_writable?
      config.writable?("ssh_enabled")
    end

    # Public: Indicate if ssh access came from higher level via policy
    #
    # Returns true or false
    def ssh_policy?
      config.final?("ssh_enabled")
    end

    # Public: Let us know if ssh access rejection is set somewhere else
    #
    # Returns a Boolean
    def ssh_inherited?
      config.inherited?("ssh_enabled")
    end

    # Public: Let us know if ssh acces rejection is set on this object
    #
    # Returns a Boolean
    def ssh_local?
      config.local?("ssh_enabled")
    end

    # Public: Retrieve the object that has the force rejection value set
    #
    # Returns an a Configurable or nil
    def ssh_source
      config.source("ssh_enabled")
    end

    # Public: Where a default value would come from if current setting is cleared.
    #
    # Returns a Configurable or nil
    def ssh_default_source
      configuration_default_entry_owner("ssh_enabled")
    end

    # Public: Where a default value would come from if current setting is cleared.
    #
    # Returns a string or nil
    def ssh_default_value
      configuration_default_entry_value("ssh_enabled")
    end
  end
end
