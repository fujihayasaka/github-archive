# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Given a merge commit for a pull request, and a new message and author,
    # create a new merge commit with the same tree.
    #
    # commit_oid - The sha of the merge commit to update the information for.
    # info       - The hash of information to update on the merge commit.
    # &block     - A block that is passed the staged raw commit and returns a
    #              signature over that commit. This is then included in the
    #              persisted commit. (Optional)
    #
    # The info argument is for specifying commit metadata. It has the
    # following structure:
    #
    #     { 'message'   => required string commit message,
    #       'committer' => required committer information hash,
    #       'author'    => optional author information hash }
    #
    # The committer and author hashes have the following members:
    #
    #     { 'name'      => required full name string,
    #       'email'     => required email address string,
    #       'time'      => required ISO8601 time string }
    #
    # The committer information hash is required; the author is optional. If
    # no author is given the committer information is used in both places.
    #
    # Returns the string oid of the newly created merge commit.
    def rewrite_merge_commit(commit_oid, info, squash = false)
      ensure_valid_full_oid(commit_oid)

      args = [commit_oid, info, squash]

      if block_given?
        base_data = send_message(:stage_signed_rewrite_merge_commit, *args)
        signature = yield base_data

        if signature.nil? || signature.empty?
          send_message(:rewrite_merge_commit, *args)
        else
          send_message(:persist_signed_rewrite_merge_commit, base_data, signature, *args)
        end
      else
        send_message(:rewrite_merge_commit, *args)
      end
    end
  end
end
