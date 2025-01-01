# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Retrieve unique, ordered contributors for a path starting
    # at a given commit.
    #
    # commit_oid         - 40 char oid string identifying starting commit
    # path               - The path to check
    # co_authors         - If true, treats emails in `Co_authored_by` trailers as authors
    # group_by_signature - If true, treat commits with same email but different name
    #                      as different authors (instead of just grouping by email)
    #
    # Returns a structure containing an array of unique author information
    # and a flag indicating if the array was truncated due to timeout or
    # data size limitations.  For each author, this will return a
    # structure with the email address, last commit SHA, time of their
    # last contribution, and count of commits they are the author of.
    #
    # The structure will look like:
    #
    #     { 'data' => [ { 'author' => 'email@github.com',
    #                     'commit' => '01234...',
    #                     'time'   => 123456,
    #                     'offset' => -28800,
    #                     'count'  => 1 },
    #                   { 'author' => email2@other.com', ... } ]
    #       'truncated' => true/false }
    #
    # Raises GitRPC::ObjectMissing if the commit_oid and/or path cannot
    # be resolved.
    def read_blob_contributors(commit_oid, path, co_authors: false, group_by_signature: false)
      raise GitRPC::ObjectMissing if path.nil? || path == ""
      ensure_valid_full_oid(commit_oid)

      cache_key = read_contributors_key(commit_oid, path, co_authors, group_by_signature)
      cache_fetch(cache_key, backend_method: :read_contributors) do
        send_message(:read_contributors, commit_oid, path, co_authors: co_authors, group_by_signature: group_by_signature)
      end
    end

    private

    # Internal: Cache key used to store the blob and repository contributors
    #
    # commit_oid         - 40 char object id string
    # path               - Path being checked (nil for a repository cache)
    # co_authors         - Whether this contribution list includes `Co_authored_by` trailers
    # group_by_signature - Whether this contribution list groups by full sig (and not just email)
    #
    # Returns a key suitable for use with memcache.
    def read_contributors_key(commit_oid, path = "", co_authors, group_by_signature)
      key_parts = [
        "read_contributors",
        commit_oid,
        sha256(path.to_s),
        GitRPC::Backend.blob_contributors_limit,
        "v1"
      ]
      key_parts << "co_authors" if co_authors
      key_parts << "group_by_signature" if group_by_signature
      content_cache_key(key_parts)
    end
  end
end
