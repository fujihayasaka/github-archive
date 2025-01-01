# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

# Client-side methods related to DGit

module GitRPC
  class Client
    # Return the replica checksum that is currently recorded in the
    # "dgit-state" file. Note that this call can fail if the file is
    # absent (which happens temporarily during every transaction) or
    # if the file is present but empty (which shouldn't happen but has
    # been observed in the wild). Also note that the value is read
    # without holding the "dgit-state" lock, so the returned value
    # might no longer be current by the time this method returns.
    def read_dgit_checksum
      dgit_state = fs_read("dgit-state")
      line = dgit_state.lines.first
      raise EmptyDGitState unless line
      line.chomp
    end

    # Runs "git dgit-state init" and returns the first line of the
    # "dgit-state" file.
    def dgit_state_init(checksum_version)
      send_message(:dgit_state_init, checksum_version)
    end

    # Public: Prune backups
    #
    # parent             - parent directory
    # max_repair_backups - number of backups to keep
    #
    # Returns a (possibly empty) Hash of |path, errstr| tuples
    # for any failures.
    def prune_backups(parent, max_repair_backups)
      send_message(:prune_backups, parent, max_repair_backups)
    end
  end
end
