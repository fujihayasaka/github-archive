# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    include GitRPC::Util

    # Public: Fetch the number of commits reachable from the passed in oid.
    #
    # oid   - The commit to start counting revisions from
    # limit - Max number of revisions to return. Defaults to 10,000
    # timeout - Maximum number of seconds that the operation can take to complete
    #
    # Returns the number of commits
    rpc_reader :fast_commit_count
    def fast_commit_count(oid, limit = 10_000, timeout = nil)
      ensure_valid_commitish(oid)

      opts = ["--count", "--use-bitmap-index", oid]

      if limit
        opts.unshift("-n", limit.to_s)
      end

      res = spawn_git("rev-list", opts, nil, {}, nil, timeout)
      if res["ok"]
        res["out"].to_i
      end
    end
  end
end
