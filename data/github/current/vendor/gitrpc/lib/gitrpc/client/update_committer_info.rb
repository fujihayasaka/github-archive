# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Update the committer info for a range of commits
    #
    # start_commit_oid  - String the commit oid for the start of the range.
    # end_commit_oid    - String the commit oid for the end of the range. Commit
    #                     information for this commit will not be updated.
    # committer         - Hash containing committer information:
    #                     'name' - String containing the committer's full name
    #                     'email' - String containing the committer's email
    #                     'time' - String or Time object containing the commit time
    #
    # Returns a String containing the oid of the updated version of
    # the `start_commit_oid` commit.
    def update_committer_info(start_commit_oid, end_commit_oid, committer)
      committer = stringify_keys(committer)

      time = committer["time"]
      committer["time"] = time.respond_to?(:iso8601) ? time.iso8601 : time

      send_message(:update_committer_info, start_commit_oid, end_commit_oid, committer)
    end
  end
end
