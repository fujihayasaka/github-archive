# frozen_string_literal: true
# typed: true

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

    # Internal: Simple async wrapper around request to
    # GitRPC::Backend.read_symbolic_ref. Should not be called directly; use
    # GitRepository::SpokesAdapter.async_read_symbolic_ref instead.
    #
    # ref       - String Ref name
    #
    # Returns a Promise that resolves to a string containing the path that the
    # symbolic ref points to, or rejects the promise with GitRPC::CommandFailed.
    def async_read_symbolic_ref(ref)
      async_send_message(:read_symbolic_ref, ref)
    end
  end
end
