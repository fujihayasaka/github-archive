# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Reapply commit history on top of another commit using git-replay
    # (merge-ort).
    #
    # Reapplies commits that are contained in the history of
    # commit_oid, but not in the history of upstream_commit_oid,
    # on top of the upstream_commit_oid, one after the other.
    #
    # This differs from `git rebase` as it only works with commit oids
    # inside a bare repo and does not modify any branches or HEAD.
    #
    # The provided committer information will be used for every created
    # commit, while author information of the individual commits
    # will be preserved.
    #
    # Merge commits are ignored during rebase.
    #
    # commit_oid          - String the commit oid for which to perform the rebase.
    # upstream_commit_oid - String the upstream commit oid to rebase on top.
    # committer           - Hash containing committer information:
    #                       'name' - String containing the committer's full name
    #                       'email' - String containing the committer's email
    #                       'time' - String or Time object containing the commit time
    # options             - Hash containing additional options.
    #                       'timeout' - Numeric specifying the maximum amount
    #                                   of seconds the rebase operation is
    #                                   allowed to take.
    #
    # Returns a String containing the oid of the last rebased commit, or nil
    # if rebasing failed (e.g. due to a merge conflict).
    def rebase(commit_oid, upstream_commit_oid, committer, options = {})
      committer = stringify_keys(committer)

      #FIXME: Symbolizing keys here is to ensure all `options` coming from
      #callers are handled properly inside GitRPC. Ultimately, all `options`
      #arguments being sent into this method should be proper keyword args, at
      #which point this symbolizing can be removed.
      #However, at the time of this commit, there are still callsites in
      #github/github that are sending string keyed hashes.
      options = symbolize_keys(options)

      options[:timeout] = options[:timeout].to_f if options[:timeout]

      time = committer["time"]
      committer["time"] = time.respond_to?(:iso8601) ? time.iso8601 : time

      send_message(:rebase, commit_oid, upstream_commit_oid, committer, **options)
    end

    # Like the above, but uses the experimental `--use-tmp-objdir` option, and returns
    # a tuple [commit_oid, dogstats] where commit_oid is nil if the rebase failed and
    # dogstats is an array of arguments intended to be fed to GitHub.dogstats.count()
    def rebase_tmp_objdir_experiment(commit_oid, upstream_commit_oid, committer, options = {})
      committer = stringify_keys(committer)

      #FIXME: Symbolizing keys here is to ensure all `options` coming from
      #callers are handled properly inside GitRPC. Ultimately, all `options`
      #arguments being sent into this method should be proper keyword args, at
      #which point this symbolizing can be removed.
      #However, at the time of this commit, there are still callsites in
      #github/github that are sending string keyed hashes.
      options = symbolize_keys(options)

      options[:timeout] = options[:timeout].to_f if options[:timeout]
      options[:short_circuit_bloated_rebases] = true

      time = committer["time"]
      committer["time"] = time.respond_to?(:iso8601) ? time.iso8601 : time

      send_message(:rebase_tmp_objdir_experiment, commit_oid, upstream_commit_oid, committer, **options)
    end
  end
end
