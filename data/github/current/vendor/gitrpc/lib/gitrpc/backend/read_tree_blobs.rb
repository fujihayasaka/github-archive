# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend

    BLOBS_PER_PAGE = 10_000

    # Public: This method will recursively read all the tree entries for the
    # given tree_id and return a summary for each blob. This summary contains
    # the `oid`, `name`, `size`, and `mode`. The `name` includes the full
    # path to the file.
    #
    # The results are paged. This is useful for trees that contain
    # a very large number of blobs. The blobs can be retrieved in smaller
    # chunks which is much much nicer on the Ruby garbage collector.
    #
    # The paging information along with the blobs are returned as a hash. The
    # following hash keys are returned:
    #
    #   {
    #     "current_page" => 0,
    #     "next_page"    => 1,
    #     "blobs"        => [ list of blob Hashes ]
    #   }
    #
    # The pages are zero-based; so the first page to request is page zero. The
    # "next_page" value denotes the next page number to request. When it is
    # `nil` then there are no more blobs to retrieve from this tree. The
    # "blobs" value will always be an Array even if that Array might be empty.
    #
    # tree_id  - The 40 character tree oid.
    # page     - The page number (zero-based)
    # per_page - The number of blobs to return per page (only for testing)
    #
    # Returns a Hash
    rpc_reader :read_tree_blobs_by_page
    def read_tree_blobs_by_page(tree_id, page, per_page = BLOBS_PER_PAGE)
      blobs = []
      next_page = nil

      return {
        "current_page" => page,
        "next_page" => next_page,
        "blobs" => blobs
      } if rugged.empty?

      tree = rugged.lookup(tree_id)
      raise(GitRPC::InvalidObject, "Invalid object type, expected tree but was #{tree.type}") unless tree.is_a?(Rugged::Tree)

      first = page * per_page
      last  = first + per_page - 1
      count = -1

      tree.walk_blobs do |root, blob|
        count += 1
        next if count < first

        if count > last
          next_page = page + 1
          break
        end

        filename = root + blob[:name]
        blobs << read_tree_blobs_build_hash(filename, blob)
      end

      return {
        "current_page" => page,
        "next_page" => next_page,
        "blobs" => blobs
      }
    end

    # Internal: Given a filename and a blob tree entry, construct a Hash
    # summary of the blob. This summary contains the `oid`, `name`, `size`,
    # and `mode`.
    #
    # filename - The filename as a String.
    # entry    - The blob entry as a Hash.
    #
    # Returns a Hash.
    def read_tree_blobs_build_hash(filename, entry)
      oid = entry[:oid]
      header = rugged.read_header(oid)
      name_encoding = set_filename_encoding(filename)

      { "oid"  => oid,
        "name" => filename,
        "size" => header[:len],
        "mode" => entry[:filemode] }
    end

  end  # Backend
end  # GitRPC
