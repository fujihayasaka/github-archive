# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

# Client implementations of server-related calls.
module GitRPC
  class Client
    # Public: Get one-, five-, and fifteen-minute load.
    #
    # Returns a three-element array of floats.
    def loadavg
      send_message(:loadavg)
    end

    # Public: Get the number of CPUs in the system.
    #
    # Returns an integer.
    def cpu_count
      send_message(:cpu_count)
    end

    # Public: Get the number of replicas on the system.
    #
    # gists_only - only count gists
    #
    # Returns an integer.
    def replica_count(options = {})
      send_message(:replica_count, options)
    end

    # Public: Read and parse /etc/github/metadata.json from the fileserver.
    #
    # Raises an error if there's a problem doing that.
    def host_metadata
      send_message(:host_metadata)
    end

    # Public: Return true if the host's repositories and lariatcache data
    # are encrypted.
    def host_encrypted?
      send_message(:host_encrypted?)
    end
  end
end
