# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Internal: Set of dummy data to use as commit author and committer.
    DEFAULT_AUTHOR = {
      "name"  => "nobody",
      "email" => "nobody@github.com",
      "time"  => "1970-01-01T00:00:00Z"
    }.freeze

    # Internal: Find or create sentinel commit in repository.
    #
    # The sentinel commit is a special commit that indicates the start of a
    # history chain. This makes it possible to debug the chain using
    # `git rev-list --first-parent`.
    #
    # The commit is also used as a stand in for missing objects that have already
    # been garbage collected.
    #
    # Returns String OID.
    def pull_history_chain_find_or_create_commit(type, expected_oid)
      if rugged.exists?(expected_oid)
        expected_oid
      else
        oid = create_tree_changes(nil, {
          "tree"      => EMPTY_TREE_OID,
          "author"    => DEFAULT_AUTHOR,
          "committer" => DEFAULT_AUTHOR,
          "message"   => "#{type}\n"
        })

        if oid != expected_oid
          raise GitRPC::Error, "expected OID be #{expected_oid}, but was #{oid}"
        end

        oid
      end
    end
  end
end
