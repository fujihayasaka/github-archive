# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Public: Find as good common ancestors as possible for a merge
    #
    # base_ref - A ref name or commit oid used as the base of comparison
    # head_ref - A ref name or commit oid used as the head for comparison
    # timeout  - (Optional) Maximum number of seconds that the operation can take to complete
    #
    # Returns the merge base commit oid as a String
    rpc_reader :merge_base
    def merge_base(base_ref, head_ref, timeout = nil)
      native_merge_base(base_ref, head_ref, "merge-base", timeout)
    end

    # Public: Find all common ancestors as possible for a merge
    #
    # base_commit_oid - A commit oid used as the base for comparison
    # head_commit_oid - A commit oid used as the head for comparison
    #
    # Returns an Array of merge base commit oids as Strings.
    rpc_reader :merge_bases
    def merge_bases(base_commit_oid, head_commit_oid)
      ensure_valid_full_oid(base_commit_oid)
      ensure_valid_full_oid(head_commit_oid)

      res = spawn_git("merge-base", ["--all", "--end-of-options", base_commit_oid, head_commit_oid])

      if res["ok"]
        res["out"].rstrip.split("\n")
      elsif res["status"] == 1
        []
      elsif res["err"] =~ /not a valid (object|commit) name/i
        raise GitRPC::InvalidObject, res["err"]
      else
        raise GitRPC::CommandFailed.new(res)
      end
    end

    # Public: Find as good common ancestors as possible for a merge
    #
    # base_commit_oid - A commit oid used as the base for comparison
    # head_commit_oid - A commit oid used as the head for comparison
    # timeout         - (Optional) Maximum number of seconds that the operation can take to complete
    #
    # Returns the merge base commit oid as a String
    rpc_reader :best_merge_base
    def best_merge_base(base_commit_oid, head_commit_oid, timeout = nil)
      ensure_valid_full_oid(base_commit_oid)
      ensure_valid_full_oid(head_commit_oid)

      native_merge_base(base_commit_oid, head_commit_oid, "best-merge-base", timeout)
    end

    rpc_reader :branch_base
    def branch_base(head_oid, base_oid, root_oid)
      ensure_valid_full_oid(head_oid)
      ensure_valid_full_oid(base_oid)
      ensure_valid_full_oid(root_oid)

      res = spawn_git("branch-base", [head_oid, base_oid, root_oid])

      if !res["ok"]
        # FIXME: the old ruby `git-branch-base` had a bug that it
        # would return `root_oid` even if `--git-dir` was set to a
        # non-git directory (or even a non-existent directory) or if
        # any of the arguments were not existing OIDs. The Go
        # `git-branch-base` correctly errors out in those situations.
        # But some unrelated tests depend on the old, buggy behavior,
        # and it's conceivable that production might hit this case
        # sometimes, too. As a temporary workaround while we fix
        # callers, imitate the old behavior:
        return root_oid
      end

      res["out"].strip
    end

    private

    # Private: Find as good common ancestors as possible for a merge
    #
    # The git-merge-base program 1.) writes a single SHA1 to stdout when a
    # common ancestor is located, 2.) exits 1 when no common ancestor exists,
    # 3.) exits 128 because either the base or head SHA1 do not exist, 4.) exits 128 or
    # something else when some kind of repository or system failure occurs.
    #
    # base_ref - A ref name or commit oid used as the base of comparison
    # head_ref - A ref name or commit oid used as the head for comparison
    # git_command - "merge-base" or "best-merge-base"
    # timeout - Maximum number of seconds that the operation can take to complete
    #
    # Returns the merge base commit oid as a String
    def native_merge_base(base_ref, head_ref, git_command = "merge-base", timeout = nil)
      raise ArgumentError if !["merge-base", "best-merge-base"].include?(git_command)

      ensure_valid_commitish(base_ref)
      ensure_valid_commitish(head_ref)

      res = spawn_git(git_command, [base_ref, head_ref], nil, {}, nil, timeout)

      if res["ok"]
        res["out"].rstrip
      elsif res["status"] == 1
        nil
      elsif res["err"] =~ /not a valid (object|commit) name/i
        raise GitRPC::InvalidObject, res["err"]
      else
        raise GitRPC::Error, res["err"]
      end
    end
  end
end
