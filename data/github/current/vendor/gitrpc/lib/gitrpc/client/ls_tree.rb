# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: List the contents of a tree object
    #
    # treeish    - Id of a tree-ish.
    # path       - Paths to show. If omitted, show the root level of the tree.
    #              (can be a string or an array of strings)
    # long       - Show object size of blob (file) entries.
    # recurse    - Recurse into sub-trees.
    # show_trees - Show tree entries even when recursing (has no effect without recurse).
    # byte_limit - limit output to this many bytes.
    #
    # Returns a result hash, containing:
    #   "entries"   - an array of arrays of columns.
    #   "truncated" - whether results were truncated by byte_limit.
    # Returns an array of arrays of columns.
    def ls_tree(treeish, options = {})
      send_message(:ls_tree, treeish, **options)
    end
  end
end
