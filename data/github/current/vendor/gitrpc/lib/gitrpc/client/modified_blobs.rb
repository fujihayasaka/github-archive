# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Finds all blobs which were changed between two commit oids.
    # Each blob hash returned will at least have a 'modified_status' key
    # denoting an addition, modification, rename, copy, deletion or type
    # change.
    #
    # A 'path' key is also returned which is the full nested path to the blob.
    # For deletions only the 'modified_status' and 'path' keys are returned.
    # For all other types of changes which result in a new blob, the new
    # blob's oid is included as 'oid', and a full blob hash (read via
    # read_blobs) is merged in.
    #
    # When a modification does not result in a new blob (for example,
    # when a submodule is modified, or a path that was a blob changes
    # type and becomes a submodule), the 'oid' key is not returned.
    #
    # All modifications that aren't deletions are stored under the 'modified'
    # key of the returned hash.
    #
    # All deletions are stored under the 'deleted' key.
    #
    # before - The old commit oid
    # after - The new commit oid
    #
    # Returns an array of simple hashes representing the blobs that changed.
    def modified_blobs(before, after)
      ensure_valid_full_oid(before)
      ensure_valid_full_oid(after)

      changed = cache_fetch(modified_blobs_key(before, after), backend_method: :modified_blobs) do
        send_message(:modified_blobs, before, after)
      end

      modified_with_oids, modified_without_oids = changed["modified"].partition { |m| m["oid"] }
      blob_oids = modified_with_oids.map { |m| m["oid"] }

      # reuse cache if we can
      blobs = read_blobs(blob_oids)

      modified_with_oids.zip(blobs) do |blob_meta, blob|
        blob_meta.merge!(blob)
      end

      changed["modified"] = modified_with_oids + modified_without_oids
      changed
    end

    def modified_blobs_key(before, after)
      repository_cache_key("modified_blobs_v3", before, after, true)
    end
  end
end
