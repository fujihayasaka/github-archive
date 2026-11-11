# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Find as good common ancestors as possible for a merge.
    #
    # commit_oid1 - A full 40-character commit oid used as the base of comparison
    # commit_oid2 - A full 40-character commit oid used as the head for comparison
    # timeout     - Maximum number of seconds that the operation can take to complete
    #
    # Returns the merge base commit oid as a String. May raise
    # GitRPC::InvalidObject if target oid is missing or not a commit.
    # Raises GitRPC::Timeout if the operation takes to long.
    def merge_base(commit_oid1, commit_oid2, timeout: nil)
      ensure_valid_full_oid(commit_oid1)
      ensure_valid_full_oid(commit_oid2)

      cache_key = content_cache_key("merge-base", commit_oid1, commit_oid2)
      cache_fetch(cache_key, backend_method: :merge_base) do
        raise GitRPC::Timeout if timeout && timeout <= 0
        send_message(:merge_base, commit_oid1, commit_oid2, timeout)
      end
    end

    # Public: Find common ancestors as possible for a merge.
    #
    # commit_oid1 - A full 40-character commit oid used as the base of comparison
    # commit_oid2 - A full 40-character commit oid used as the head for comparison
    #
    # Returns an Array of commit oids as Strings. May raise
    # GitRPC::InvalidObject if target oid is missing or not a commit.
    # Raises GitRPC::Timeout if the operation takes to long.
    def merge_bases(commit_oid1, commit_oid2)
      ensure_valid_full_oid(commit_oid1)
      ensure_valid_full_oid(commit_oid2)

      send_message(:merge_bases, commit_oid1, commit_oid2)
    end

    # Public: Find the best merge base for merging head to base. This is very
    # much like `merge_base` except that if base and head have multiple merge
    # bases, it chooses the best merge base among the alternatives more
    # intelligently than "git merge-base".
    #
    # commit_oid1 - A full 40-character commit oid used as the base of comparison
    # commit_oid2 - A full 40-character commit oid used as the head for comparison
    # timeout     - Maximum number of seconds that the operation can take to complete
    #
    # Returns the merge base commit oid as a String. May raise
    # GitRPC::InvalidObject if target oid is missing or not a commit.
    # Raises GitRPC::Timeout if the operation takes to long.
    def best_merge_base(commit_oid1, commit_oid2, timeout: nil)
      ensure_valid_full_oid(commit_oid1)
      ensure_valid_full_oid(commit_oid2)

      cache_key = content_cache_key("best-merge-base", commit_oid1, commit_oid2)
      cache_fetch(cache_key, backend_method: :best_merge_base) do
        raise GitRPC::Timeout if timeout && timeout <= 0
        send_message(:best_merge_base, commit_oid1, commit_oid2, timeout)
      end
    end

    # Public: Find the best comparison base commit for a branch
    #
    # head_oid - The branch head ref
    # base_oid - The ref of the branch that head_oid was originally based on
    # root_oid - The SHA1 of the commit where head_oid initially started
    #
    # Returns a string containing the 40-char oid of the best
    # comparison base commit, or raises GitRPC::CommandFailed.
    def branch_base(head_oid, base_oid, root_oid)
      ensure_valid_full_oid(head_oid)
      ensure_valid_full_oid(base_oid)
      ensure_valid_full_oid(root_oid)

      send_message(:branch_base, head_oid, base_oid, root_oid)
    end
  end
end
