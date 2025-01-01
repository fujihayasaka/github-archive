# rubocop:disable Style/FrozenStringLiteralComment
# RPC calls for executing system and git commands for a repository.
require "gitrpc/native"

module GitRPC
  class Backend
    GIT_RO_WHITELIST = [
      # Git builtins
      "ls-tree",
      "log",
      "blame",
      "rev-list",
      "rev-parse",
      "diff",
      "blame-tree",
      "for-each-ref",
      "show",
      "diff-tree",
      "shortlog",
      "config",
      "ref-contains",
      "grep",

      # Custom GitHub helpers
      "best-merge-base",
      "branch-base",
      "distinct-commits",
      "condense-diff",
      "backup",
      "backup-wiki",
      "janitor",
      "scan-creds",

      # Custom NW helpers
      "nw-linked", # TODO: remove
      "nw-find-tokens",

      # For push mirroring
      "push",

      # These only read, but output can vary amongst the backends
      # so we still want to route to all servers
      #'nw-usage',
      #'nw-du',
    ].to_set.freeze

    GIT_WHITELIST = GIT_RO_WHITELIST + [
      "clone",
      "copy-fork",
      "dgit-state",
      "fetch",
      "fetch-commits",
      "get-maint-size",
      "get-unpacked-size",
      "hash-object",
      "help", # Not needed, but noop, used for tests
      "last-fsck",
      "linguist",
      "merge-base",
      "mirror",
      "nw-clone",
      "nw-du",
      "nw-gc",
      "nw-link",
      "nw-repack",
      "nw-rm",
      "nw-sync",
      "nw-unlink",
      "nw-usage",
      "push-log",
      "repack",
      "revert-commit",
      "scout",
      "symbolic-ref",
      "update-ref",
      "verify-backup"
    ].to_set.freeze

    # Internal: Low level process spawning interface.
    def spawn(argv, input = nil, env = {}, byte_limit = nil, timeout = nil)
      res = native.spawn(argv, input, env, :max => byte_limit, :timeout => timeout)
      res = stringify_keys(res)
      res["options"] = stringify_keys(res["options"])
      res
    rescue Progeny::TimeoutExceeded
      raise GitRPC::Timeout.new(argv: argv)
    rescue => e
      raise GitRPC::SpawnFailure.new(e, argv)
    end

    # Internal: Low level process spawning interface for read only.
    def spawn_ro(argv, input = nil, env = {}, byte_limit = nil)
      spawn(argv, input, env, byte_limit)
    end

    # Internal: Execute a git command and return the result output.
    def spawn_git(command, argv = [], input = nil, env = {}, byte_limit = nil, timeout = nil, git_opts = [])
      git_opts.unshift("--git-dir", @path)
      argv = ["git", *git_opts, command, *argv]
      spawn(argv, input, env, byte_limit, timeout).tap do |res|
        raise GitRPC::CommandBusy if res["status"] == GITMON_BUSY
      end
    end

    def spawn_git_ro(command, argv = [], input = nil, env = {}, byte_limit = nil)
      unless GIT_RO_WHITELIST.include?(command)
        raise "#{command} isn't read only"
      end

      spawn_git(command, argv, input, env, byte_limit)
    end

    def spawn_git_and_count_stdout_lines(command, argv = [], env = {})
      git_opts = ["--git-dir", @path]
      argv = ["git", *git_opts, command, *argv]
      res = native.spawn_and_count_stdout_lines(argv, env)
      res = stringify_keys(res)
      res
    end

    NOT_GIT_REPO = "fatal: not a git repository"
    private_constant :NOT_GIT_REPO

    # Internal: A version of spawn_git that checks the result and raises
    # appropriate error classes on failure, attempting to match the semantics
    # of the exceptions raised by rugged-based RPC calls.
    def checked_spawn_git!(...)
      res = spawn_git(...)
      return res if res["ok"]
      err = res["err"].chomp
      msg = "#{err} (exit #{res["status"]})"
      # TODO there are certainly other error conditions that need to be checked
      # here but we will need to disover them as they crop up.
      if err.include?(NOT_GIT_REPO) # empty or malformed directory
        raise ::GitRPC::InvalidRepository, msg
      else
        raise ::GitRPC::Failure.new(::GitRPC::CommandFailed.new(res))
      end
    end

    # Public: Build a git command without immediately executing it
    #
    # Note that if you use this interface, you should rescue the
    # Progeny::TimeoutExceeded exception and convert it to a
    # GitRPC::Timeout if need be.  Unlike `spawn_git`, this API will not
    # do that for you.
    #
    # XXX timeout argument is a hack until we have per-call timeouts.
    def build_git(command, argv = [], input = nil, env = {}, timeout = nil)
      git_opts = ["--git-dir", @path]
      argv = ["git", *git_opts, command, *argv]
      native.build(argv, input, env, timeout)
    end
  end
end
