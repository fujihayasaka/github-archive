# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Get the number of git upload processes running on the server.
    #
    # Returns an integer, or raises GitRPC::CommandFailed.
    def fetches_running
      send_message(:fetches_running)
    end

    # Public: Get the number of git operations running on the server.
    #
    # Returns an integer, or raises GitRPC::CommandFailed.
    def git_operations_running
      send_message(:git_operations_running)
    end
  end
end
