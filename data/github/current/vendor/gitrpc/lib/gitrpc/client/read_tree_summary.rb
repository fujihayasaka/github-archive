# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Fetch a summary of all trees in this Repository. The result
    # includes the blob names with path prefixes, blob content, and blob oids.
    #
    # commit_id - The 40 char sha1 oid of the commit whose tree should be
    #             read. This must be a commit oid, not a tree oid.
    #
    # Returns an array of hashes:
    #
    #     { 'oid'       => 40 char sha1 oid of the blob,
    #       'name'      => filename (including the path prefix),
    #       'content'   => the (possibly truncated) content of the file as a string,
    #       'size'      => the untruncated size of the blob,
    #       'truncated' => true when the content string is truncated, false otherwise }
    #
    # Note that only ~1MB of total blob content data will be returned across
    # all entries. Entries are returned for subsequent blobs but their data
    # will be truncated.
    def read_tree_summary_recursive(commit_id)
      ensure_valid_full_oid(commit_id)

      cache_fetch tree_summary_recursive_key(commit_id), backend_method: :read_tree_summary_recursive do
        files = send_message(:read_tree_summary_recursive, commit_id)
        mark_file_and_name_encoding(files)
      end
    end

    def tree_summary_recursive_key(commit_id)
      content_cache_key("tree_summary_recursive", "v2", commit_id)
    end

    def mark_file_and_name_encoding(files)
      files.each do |file|
        GitRPC::Encoding.tag_compatible(file["content"], file["encoding"])
        GitRPC::Encoding.tag_compatible(file["name"], file["name_encoding"])
      end
      files
    end
  end
end
