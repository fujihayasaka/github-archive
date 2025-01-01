# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Get the tree diff for a commit or pair of commits.
    # This is only a tree diff so the actual blob diffs are't included. Also
    # since we're not touching any blob data here there's no rename detection.
    #
    # commit1_oid - a full 40-character commit oid
    # commit2_oid - (optional) a full 40-character commid oid
    # paths       - a path to restrict the diff to
    # diff_trees  - allow the diffing of trees, not just commits
    #
    # Returns an array of Hashes like:
    # {
    #   "status" => "modified",
    #   "old_file" => {
    #     "oid" => "deadbeef",
    #     "path" => "docs/README.md",
    #     "mode" => 0100644,
    #   },
    #   "new_file" => {
    #     "oid" => "deadbeef2",
    #     "path" => "docs/README.md",
    #     "mode" => 0100644,
    #   }
    # }
    def read_tree_diff(commit1_oid, commit2_oid = nil, paths: [], diff_trees: false)
      ensure_valid_full_oid(commit1_oid)
      ensure_valid_full_oid(commit2_oid) if commit2_oid

      key = content_cache_key("read_tree_diff", commit1_oid, commit2_oid, paths, "v2")

      cache_fetch(key, backend_method: :read_tree_diff) do
        send_message(:read_tree_diff, commit1_oid, commit2_oid, paths:, diff_trees:)
      end
    end
  end
end
