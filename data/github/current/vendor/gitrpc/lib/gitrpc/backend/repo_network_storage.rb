# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Raised when calculating free space fails.
    class CalculateFreeSpaceFailed < GitRPC::CommandFailed
    end

    # Raised when calculating disk usage fails.
    class CalculateDiskUsageFailed < GitRPC::CommandFailed
    end

    # Raised when calculating unpacked size fails.
    class CalculateUnpackedSizeFailed < GitRPC::CommandFailed
    end

    # Raised when calculating maintenance size fails.
    class CalculateMaintSizeFailed < GitRPC::CommandFailed
    end

    # Report available disk space (in KB) on the partition holding the
    # repo network.
    def free_space
      # Sometimes `self.path` points to a path that doesn't exist yet,
      # e.g., when we're trying to determine if a target partition has
      # enough space to receive a new repo network.  Walk up the tree
      # until we find a path that actually exists, on which we can run
      # `df`.
      dir = self.path
      while dir && dir != "." && !File.exist?(dir)
        dir = File.dirname(dir)
      end

      res = spawn(["df", "-k", dir])
      raise CalculateFreeSpaceFailed.new(res) if !res["ok"]
      df_output = res["out"]
      line = df_output.split("\n")[1]
      line.split[3].to_i
    end
    rpc_reader :free_space, no_git_repo: true

    # Report disk space consumed by a repo network (in KB).
    # Note that `git nw-usage` stores the result in a file `usage` in the
    # network directory.
    def nw_usage
      res = spawn_git("nw-usage")
      raise CalculateDiskUsageFailed.new(res) if !res["ok"]
      res["out"].to_i
    end
    rpc_reader :nw_usage, no_git_repo: true

    # Report disk space consumed by the objects in a given fork/repository
    # inside a network.
    #
    # This is an accurate measure perfomed by calculating the on-disk size
    # of all the reachable objects in the repository
    def repo_disk_usage(ignore_refs = [])
      args = ignore_refs.map { |r| "--exclude=#{r}" } +
        ["--all", "--objects", "--disk-usage", "--use-bitmap-index"]

      res = spawn_git("rev-list", args)
      raise CalculateDiskUsageFailed.new(res) if !res["ok"]
      res["out"].to_i
    end
    rpc_reader :repo_disk_usage

    # Report the total size of all pack files that need to be repacked, in
    # MB.
    def get_unpacked_size
      res = spawn_git("get-unpacked-size")
      raise CalculateUnpackedSizeFailed.new(res) if !res["ok"]
      res["out"].to_i
    end
    rpc_reader :get_unpacked_size

    # Report the estimated size that would be required to run network
    # maintenance, in MB.
    def get_maint_size
      res = spawn_git("get-maint-size")
      raise CalculateMaintSizeFailed.new(res) if !res["ok"]
      res["out"].to_i
    end
    rpc_reader :get_maint_size, no_git_repo: true
  end
end
