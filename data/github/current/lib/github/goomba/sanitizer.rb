# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  module Sanitizer
    # Constructs a Goomba::Sanitizer based on the given allowlist.
    #
    # allowlist - a Sanitize-style allowlist Hash
    #
    # Returns a Goomba::Sanitizer.
    def self.from_allowlist(allowlist)
      allowlist = allowlist.dup
      # h7/h8 are in the default allowlist, but aren't standard HTML elements.
      # Goomba complains if we try to allowlist them. Hopefully no one's using
      # these in their content.
      allowlist[:elements] = allowlist.fetch(:elements, []) - %w[h7 h8]

      Goomba::Sanitizer.from_hash(allowlist)
    end
  end
end
