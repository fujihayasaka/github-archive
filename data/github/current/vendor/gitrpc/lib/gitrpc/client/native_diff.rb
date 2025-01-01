# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Get the raw text for a diff
    #
    # commit1_oid - a commit sha1
    # commit2_oid - a commit sha1
    # timeout - Maximum number of seconds that the operation can take to complete
    #
    # Returns the raw diff text as a String
    def native_diff_text(commit1_oid, commit2_oid = nil, paths: [], full_index: false, timeout: nil)
      paths = Array(paths)
      ensure_valid_full_oid(commit1_oid)
      ensure_valid_full_oid(commit2_oid) if commit2_oid

      cache_key = diff_text_key("diff-text", commit1_oid, commit2_oid, "v2", paths, full_index: full_index)
      cache_fetch(cache_key, backend_method: :native_diff_text) do
        raise GitRPC::Timeout if timeout && timeout <= 0
        send_message(:native_diff_text, commit1_oid, commit2_oid, paths, full_index: full_index, timeout: timeout)
      end
    end

    # Public: Get the raw text for a diff in patch format
    #
    # commit1_oid - a commit sha1
    # commit2_oid - a commit sha1
    # timeout - Maximum number of seconds that the operation can take to complete
    #
    # Returns the diff text in patch format as a String
    def native_patch_text(commit1_oid, commit2_oid = nil, full_index: false, timeout: nil)
      ensure_valid_full_oid(commit1_oid)
      ensure_valid_full_oid(commit2_oid) if commit2_oid

      cache_key = diff_text_key("patch-text", commit1_oid, commit2_oid, "v2", full_index: full_index)
      cache_fetch(cache_key, backend_method: :native_patch_text) do
        raise GitRPC::Timeout if timeout && timeout <= 0
        send_message(:native_patch_text, commit1_oid, commit2_oid, full_index: full_index, timeout: timeout)
      end
    end

    # Internal: Cache key used to store the diff.
    #
    # type    - The type of call to cache
    # commit1 - 40 char object id string.
    # commit2 - 40 char object id string.
    #
    # Returns a String key suitable for use with memcache.
    def diff_text_key(type, commit1, commit2, version, paths = [], full_index:)
      args = [commit1, commit2, type, version]
      unless paths.empty?
        args << sha256(paths)
      end
      args << sha256("{:full_index=>#{full_index}}")
      content_cache_key(*args)
    end
  end
end
