# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Pack unpacked objects in a repository
    #
    # Returns nil, or raises GitRPC::CommandFailed.
    def repack
      send_message(:repack)
    end
  end
end
