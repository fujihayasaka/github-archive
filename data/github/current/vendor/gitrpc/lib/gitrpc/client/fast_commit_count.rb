# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Fetch the number of commits reachable from the passed in oid.
    #
    # oid   - The commit to start counting revisions from
    # limit - Max number of revisions to return. Defaults to 10,000
    # timeout - Maximum number of seconds that the operation can take to complete
    #
    # Returns the number of commits
    def fast_commit_count(oid, limit = 10_000, timeout: nil)
      ensure_valid_full_oid(oid)

      cache_key = repository_cache_key("fast_commit_count", oid, limit)
      cache_fetch(cache_key, backend_method: :fast_commit_count) do
        raise GitRPC::Timeout if timeout && timeout <= 0
        send_message(:fast_commit_count, oid, limit, timeout)
      end
    end
  end
end
