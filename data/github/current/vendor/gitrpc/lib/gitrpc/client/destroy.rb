# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Destroy a network replica.
    #
    # nwpath - network path to destroy.  (This must match the rpc object
    #   used to call this method.)
    #
    # Returns nil on success.
    # Raises GitRPC::IllegalPath if the path doesn't match.
    def destroy_network_replica(userpath)
      send_message(:destroy_network_replica, userpath)
    end
  end
end
