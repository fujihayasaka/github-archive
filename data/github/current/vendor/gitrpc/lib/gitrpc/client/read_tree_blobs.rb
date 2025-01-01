# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client

    # Public: Fetch a summary of all trees in this Repository and return the
    # results in "pages" of fixed size. All the blobs in the tree can be
    # returned by requestign subsequent pages of data. The returned blobs
    # contain the name, oid, size, and file mode of the blob. The actual blob
    # data is **not** returned by this method.
    #
    # tree_id - The 40 char sha1 oid of the tree (not a commit oid).
    # page    - The page number (zero-based).
    #
    # Returns a Hash
    #
    #   { 'current_page' => current page number (zero based),
    #     'next_page'    => next page number or nil if this is the last page,
    #     'blobs'        => Array of blob Hashes }
    #
    def read_tree_blobs_by_page(tree_id, page)
      ensure_valid_full_oid(tree_id)

      cache_key = content_cache_key("read_tree_blobs_by_page", "v2", tree_id, page, true)

      cache_fetch(cache_key, backend_method: :read_tree_blobs_by_page) do
        send_message(:read_tree_blobs_by_page, tree_id, page)
      end
    end

  end  # Client
end  # GitRPC
