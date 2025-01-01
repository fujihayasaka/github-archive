# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    # Public: Get a git configuration value.
    #
    # name - the String config option name.
    #
    # Returns the String option value, or nil if the option is not set.
    rpc_reader :config_get
    def config_get(name)
      res = spawn_git("config", ["--local", "--get", "--end-of-options", name])
      case res["status"]
      when 0
        res["out"].chomp
      when 1
        nil
      else
        err = res["err"].chomp
        msg = "#{err} (exit #{res["status"]})"
        if err.include?(NOT_GIT_REPO)
          raise ::GitRPC::InvalidRepository, msg
        else
          raise ::GitRPC::Failure.new(::GitRPC::CommandFailed.new(res))
        end
      end
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
    rpc_writer :config_store
    def config_store(name, value)
      if ![String, TrueClass, FalseClass].any? { |klass| value.is_a?(klass) }
        raise TypeError, "no implicit conversion into String"
      end
      checked_spawn_git!("config", ["--local", "--end-of-options", name, value.to_s])
      nil
    end

    # Public: Delete a git configuration value.
    # DANGER: This updates hard state and must not be called directly.
    # Use GitHub::DGit::Util.config_delete which does the proper locking.
    #
    # name - the String config option name.
    #
    # Returns true if the option was present, or false otherwise.
    rpc_writer :config_delete
    def config_delete(name)
      res = spawn_git("config", ["--local", "--unset", "--end-of-options", name])
      case res["status"]
      when 0
        true
      when 5
        false
      else
        err = res["err"].chomp
        msg = "#{err} (exit #{res["status"]})"
        if err.include?(NOT_GIT_REPO)
          raise ::GitRPC::InvalidRepository, msg
        else
          raise ::GitRPC::Failure.new(::GitRPC::CommandFailed.new(res))
        end
      end
    end

    private

    # Private: Get the current configuration.
    #
    # Returns the Rugged::Config instance for the current repository.
    def config
      rugged.config
    end
  end
end
