# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Tell whether a file has changed between two commits
    #
    # file   - filename
    # before - starting commit
    # after  - ending commit
    #
    # Returns true or false, or raises GitRPC::CommandFailed.
    def file_changed?(file, before, after)
      send_message(:file_changed?, file, before, after)
    end

    # Public: Return a raw diff.
    #
    # before - starting commit
    # after  - ending commit
    #
    # Returns an array of raw diff lines, or raises GitRPC::CommandFailed.
    def raw_diff(before, after)
      send_message(:raw_diff, before, after)
    end

    # Public: Return a shortstat for a commit range.
    #
    # range - a revision range string
    #
    # Returns a shortstat string, or raises GitRPC::CommandFailed.
    def diff_shortstat(range)
      send_message(:diff_shortstat, range)
    end

    # Public: Compare the content and mode of blobs found via two tree objects
    #
    # before             - a tree-ish
    # after              - a tree-ish
    # include_tree_entry - show tree entry itself (implies recurse)
    # recurse            - recurse into sub-trees
    #
    # Returns an array of [meta, path] arrays, or raises GitRPC::CommandFailed.
    def diff_tree(before, after, options = {})
      send_message(:diff_tree, before, after, **options)
    end

    # Public: Checks to see if a rename exists at a given commit oid
    #
    # commit_oid         - commit SHA to run git diff-tree on
    # similarity_index   - how similar the file content must be to be considered a rename
    # new_path           - path used to determine which file was renamed
    #
    # Returns an array of [similarity, old_path, new_path] arrays, or raises GitRPC::CommandFailed.
    def diff_tree_path_renamed(commit_oid, options = {})
      send_message(:diff_tree_path_renamed, commit_oid, **options)
    end
  end
end
