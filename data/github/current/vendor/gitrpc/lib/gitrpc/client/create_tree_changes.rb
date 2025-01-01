# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client

    # Public: Create a new commit with a set of changes to an existing commit.
    # The changes specified may be applied as offsets to an existing tree (e.g.,
    # only modify the `README`) or as a whole new tree that replaces the prior
    # tree entirely.
    #
    # parent    - The oid string of the parent commit or nil to create
    #             a commit with no parents and an entirely new tree.
    # info      - The commit information hash. See the extended documention for
    #             details on this data structure.
    # files     - Hash of filename => data pairs. The filename must be a
    #             string and may include slashes into subtrees. The data should
    #             be a Hash with the following acceptable keys.
    #
    #             data   - String blob content of the new tree entry
    #             mode   - Numeric (octal) file mode, e.g. 0100644 or 0100755
    #             source - String path of an old tree entry to remove (for file
    #                      moves). Will also provide mode and data if not
    #                      overridden.
    #
    #             For simplicity, the data may also be a string with the entire
    #             blob content of the new tree entry.
    # signature - String signature to include in commit. (Optional)
    # &block    - A block that is passed the staged raw commit and returns a
    #             signature over that commit. This is then included in the
    #             persisted commit. (Optional)
    #
    # The info argument is for specifying commit metadata. It has the
    # following structure:
    #
    #     { "message"   => required string commit message,
    #       "committer" => required committer information hash,
    #       "author"    => optional author information hash }
    #
    # The committer and author hashes have the following members:
    #
    #     { "name"      => required full name string,
    #       "email"     => required email address string,
    #       "time"      => optional ISO8601 time string }
    #
    # The committer information hash is required; the author is optional. If
    # no author is given the committer information is used in both places.
    #
    # Returns the string oid of the newly created commit.
    def create_tree_changes(parent, info, files = nil, signature = nil)
      # Set time before calling the backend.  If the servers set their own
      # commit timestamp, it can disagree.
      now = Time.now.utc.iso8601
      %w[committer author].each do |key|
        if info.has_key?(key)
          info[key]["time"] ||= now
        end
      end

      args = [parent, info, files]

      if signature || block_given?
        base_data, tree_id = send_message(:stage_signed_tree_changes, *args)
        signature ||= yield base_data
        info["tree"] ||= tree_id

        if signature.nil? || signature.empty?
          send_message(:create_tree_changes, *args)
        else
          send_message(:persist_signed_tree_changes, base_data, signature, *args)
        end
      else
        send_message(:create_tree_changes, *args)
      end
    end

    def create_tree(files, base_tree_oid = nil)
      send_message(:create_tree, files, base_tree_oid)
    end
  end
end
