# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: show only commits reachable from <ref> that are not reachable from any other branch
    #
    # ref     - a ref
    # exclude - exclude commits that are reachable from any oid in this array
    # count   - count the commits instead of listing them
    # new_syntax - use the new reference+sha syntax ref@{sha} which is unambiguous
    #
    # Returns an array of commit oid strings, or an integer if count == true.
    # Raises GitRPC::CommandFailed on failure.
    def distinct_commits(ref, options = {})
      send_message(:distinct_commits, ref, **options)
    end
  end
end
