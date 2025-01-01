# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    # Public: Get the value of a symbolic reference
    def symbolic_ref(ref)
      ensure_valid_refname(ref)

      send_message(:symbolic_ref, ref)
    end
  end
end
