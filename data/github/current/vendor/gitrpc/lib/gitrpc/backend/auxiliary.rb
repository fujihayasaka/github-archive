# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

# Misc RPC calls used primarily for troubleshooting, tests, and network analysis.

module GitRPC
  class Backend
    # These methods are writers to test dgit.
    rpc_writer :echo, no_git_repo: true
    def echo(obj = nil)
      obj
    end

    rpc_writer :echo_kwarg, no_git_repo: true
    def echo_kwarg(arg, kwarg:)
      [arg, kwarg]
    end

    rpc_writer :echo_options, no_git_repo: true
    def echo_options
      @options
    end

    rpc_writer :slow, no_git_repo: true
    def slow(time)
      sleep time
      "OK"
    end

    rpc_reader :slow_reader, no_git_repo: true
    def slow_reader(time)
      sleep time
      "OK"
    end

    rpc_writer :rand, no_git_repo: true
    def rand
      Kernel.rand
    end

    rpc_reader :one_rand, no_git_repo: true
    def one_rand
      Kernel.rand
    end

    rpc_writer :spawn_rand, output_varies: true, no_git_repo: true
    def spawn_rand
      spawn(["head", "-c8", "/dev/random"])
    end

    rpc_reader :online?, no_git_repo: true
    def online?
      true
    end

    # Error out of GitRPC::Backend.
    #
    # error - The error to raise with.
    #
    # Returns nothing.
    rpc_reader :boomtown, no_git_repo: true
    def boomtown(error)
      raise error
    end

    rpc_writer :boomwriter, no_git_repo: true
    def boomwriter(error)
      raise error
    end
  end
end
