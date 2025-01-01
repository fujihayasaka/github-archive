# typed: true
# frozen_string_literal: true

module GitRPC
  class Client
    # Internal: Simple wrapper around request to
    # GitRPC::Backend.read_symbolic_ref. Should not be called directly; use
    # GitRepository::SpokesAdapter.read_symbolic_ref instead.
    #
    # ref       - String Ref name
    #
    # Returns a string containing the path that the symbolic ref points to,
    # or raises GitRPC::CommandFailed.
    def read_symbolic_ref(ref)
      send_message(:read_symbolic_ref, ref)
    end
  end
end
