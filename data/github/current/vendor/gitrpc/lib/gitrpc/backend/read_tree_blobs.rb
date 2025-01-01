# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend

    BLOBS_PER_PAGE = 10_000

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
      first = page * per_page
      res = checked_spawn_git!("ls-tree", ["-l", "-r", "-z", "--blobs", "--skip=#{first}", "--max-count=#{per_page + 1}", tree_id])
      lines = res["out"].split("\0")
      next_page = if lines.length == per_page + 1
        # Remove the entry which we over-read to check if there were more entries.
        lines.pop
        page + 1
      else
        nil
      end

      blobs = lines.map do |ln|
        data, filename = ln.split("\t", 2)
        mode, _, oid, size = data.force_encoding("US-ASCII").split(" ")
        filename.force_encoding("UTF-8")
        set_filename_encoding(filename)

        {
          "oid" => oid,
          "name" => filename,
          "size" => size.to_i,
          "mode" => mode.to_i(8),
        }
      end

      {
        "current_page" => page,
        "next_page" => next_page,
        "blobs" => blobs,
      }
    end
  end  # Backend
end  # GitRPC
